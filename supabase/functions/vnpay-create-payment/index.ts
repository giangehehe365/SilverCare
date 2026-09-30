// Supabase Edge Function: vnpay-create-payment
//
// Sinh URL thanh toán VNPay (môi trường SANDBOX) cho một hóa đơn, và tạo sẵn
// một dòng "payments" ở trạng thái "Chờ xác nhận" để đối chiếu khi VNPay gọi
// IPN xác nhận kết quả (xem function vnpay-ipn).
//
// Vì sao phải làm ở server (Edge Function) chứ không làm thẳng ở trình duyệt:
//   VNPay yêu cầu ký (HMAC-SHA512) toàn bộ tham số bằng "Hash Secret" của
//   merchant. Khóa này TUYỆT ĐỐI không được đưa xuống client — nếu lộ, ai
//   cũng có thể tự tạo URL thanh toán giả và đánh lừa hệ thống.
//
// Cấu hình cần thiết (chạy 1 lần, xem hướng dẫn đầy đủ ở cuối):
//   supabase secrets set VNPAY_TMN_CODE=xxxxxxx
//   supabase secrets set VNPAY_HASH_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
//   supabase secrets set VNPAY_PAY_URL=https://sandbox.vnpayment.vn/paymentv2/vpcpay.html
//
// Triển khai:
//   supabase functions deploy vnpay-create-payment
//
// Gọi từ client (người dùng đã đăng nhập, gia đình hoặc admin/manager):
//   const { data, error } = await sb.functions.invoke('vnpay-create-payment', {
//     body: { invoice_id: 123, return_url: window.location.origin + '/Home/Billing' }
//   });
//   if (data?.paymentUrl) window.location.href = data.paymentUrl;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHash } from "node:crypto";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
// .trim() để tránh lỗi "Sai chữ ký" do copy-paste dính khoảng trắng/xuống
// dòng thừa khi set secret — một lỗi rất hay gặp và không thể nhìn thấy bằng mắt.
const VNPAY_TMN_CODE = (Deno.env.get("VNPAY_TMN_CODE") ?? "").trim();
const VNPAY_HASH_SECRET = (Deno.env.get("VNPAY_HASH_SECRET") ?? "").trim();
const VNPAY_PAY_URL = Deno.env.get("VNPAY_PAY_URL") ?? "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html";
// Mỗi Terminal VNPay được cấu hình sẵn 1 thuật toán checksum cố định (xem ở
// trang quản trị Terminal, mục "Kiểu mã hóa") — merchant KHÔNG được tự chọn
// khác đi. Terminal cũ dùng MD5/SHA256 (đi kèm vnp_Version=2.0.0), Terminal
// mới hơn dùng HMACSHA512 (đi kèm vnp_Version=2.1.0). Đặt qua secret để đổi
// mà không cần sửa code, phòng khi VNPay nâng cấp Terminal lên HMACSHA512 sau.
const VNPAY_HASH_TYPE = (Deno.env.get("VNPAY_HASH_TYPE") ?? "HMACSHA512").trim().toUpperCase();
const VNPAY_VERSION = VNPAY_HASH_TYPE === "MD5" || VNPAY_HASH_TYPE === "SHA256" ? "2.0.0" : "2.1.0";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status: number): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}

// Thuật toán HMACSHA512 (Terminal mới, vnp_Version 2.1.0): encodeURIComponent()
// từng value rồi thay "%20" bằng "+" (kiểu application/x-www-form-urlencoded),
// nối lại bằng "&" sau khi đã sắp xếp các key theo thứ tự alphabet.
function buildSignDataHmac(params: Record<string, string>): string {
    const sortedKeys = Object.keys(params).sort();
    return sortedKeys
        .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k]).replace(/%20/g, "+")}`)
        .join("&");
}

async function hmacSHA512(key: string, data: string): Promise<string> {
    const enc = new TextEncoder();
    const cryptoKey = await crypto.subtle.importKey(
        "raw",
        enc.encode(key),
        { name: "HMAC", hash: "SHA-512" },
        false,
        ["sign"],
    );
    const sig = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(data));
    return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Thuật toán MD5 (Terminal cũ, vnp_Version 2.0.0): chỉ lấy các field bắt đầu
// bằng "vnp_"/"user_" có giá trị khác rỗng, nối RAW "key=value" (KHÔNG
// URL-encode) theo thứ tự alphabet, rồi MD5(secretKey + chuỗi đó). Đây là
// công thức cũ của VNPay — khác hẳn HMACSHA512, không thể dùng lẫn.
function buildSignDataMd5(params: Record<string, string>): string {
    return Object.keys(params)
        .filter((k) => (k.startsWith("vnp_") || k.startsWith("user_")) && params[k] !== "" && params[k] != null)
        .sort()
        .map((k) => `${k}=${params[k]}`)
        .join("&");
}

function md5Hex(data: string): string {
    return createHash("md5").update(data, "utf-8").digest("hex");
}

// Ký toàn bộ params theo đúng thuật toán mà Terminal đang cấu hình
// (VNPAY_HASH_TYPE) — trang quản trị Terminal của VNPay ("Kiểu mã hóa") ghi
// rõ Terminal dùng thuật toán nào, merchant phải khớp đúng, không được tự chọn.
async function computeSecureHash(params: Record<string, string>): Promise<string> {
    if (VNPAY_HASH_TYPE === "MD5") {
        return md5Hex(VNPAY_HASH_SECRET + buildSignDataMd5(params));
    }
    return await hmacSHA512(VNPAY_HASH_SECRET, buildSignDataHmac(params));
}

// VNPay yêu cầu vnp_CreateDate/vnp_ExpireDate theo GIỜ VIỆT NAM (UTC+7), bất kể
// máy chủ chạy ở múi giờ nào. Supabase Edge Function chạy trên Deno Deploy với
// đồng hồ hệ thống là UTC — nếu lấy trực tiếp d.getHours()/getDate() (giờ local
// của máy chủ = UTC) thì mốc thời gian gửi cho VNPay sẽ bị lùi 7 tiếng so với
// giờ VNPay đang tính, khiến giao dịch bị coi là hết hạn ngay khi vừa tạo.
// Cách khắc phục: cộng thẳng 7 giờ vào epoch (timezone-independent) rồi đọc
// lại bằng các hàm getUTC*() để không phụ thuộc múi giờ của máy chủ.
function formatVnpDate(d: Date): string {
    const vnTime = new Date(d.getTime() + 7 * 60 * 60 * 1000);
    const pad = (n: number) => n.toString().padStart(2, "0");
    return (
        vnTime.getUTCFullYear().toString() +
        pad(vnTime.getUTCMonth() + 1) +
        pad(vnTime.getUTCDate()) +
        pad(vnTime.getUTCHours()) +
        pad(vnTime.getUTCMinutes()) +
        pad(vnTime.getUTCSeconds())
    );
}

Deno.serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }
    if (req.method !== "POST") {
        return jsonResponse({ error: "Method not allowed" }, 405);
    }
    if (!VNPAY_TMN_CODE || !VNPAY_HASH_SECRET) {
        return jsonResponse(
            { error: "Chưa cấu hình VNPAY_TMN_CODE / VNPAY_HASH_SECRET trên Edge Function." },
            500,
        );
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const callerToken = authHeader.replace("Bearer ", "");
    if (!callerToken) {
        return jsonResponse({ error: "Thiếu token xác thực." }, 401);
    }

    // Dùng client gắn JWT của người gọi để MỌI truy vấn đều đi qua đúng RLS
    // hiện có (gia đình chỉ thấy hóa đơn của người thân mình) — không dùng
    // service_role ở function này để tránh vô tình bỏ qua kiểm tra quyền.
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
        global: { headers: { Authorization: `Bearer ${callerToken}` } },
    });

    const { data: callerUser, error: userError } = await callerClient.auth.getUser();
    if (userError || !callerUser?.user) {
        return jsonResponse({ error: "Token không hợp lệ." }, 401);
    }

    let body: { invoice_id?: number; return_url?: string };
    try {
        body = await req.json();
    } catch {
        return jsonResponse({ error: "Payload không hợp lệ." }, 400);
    }

    const invoiceId = body.invoice_id;
    const returnUrl = body.return_url;
    if (!invoiceId || !returnUrl) {
        return jsonResponse({ error: "Thiếu invoice_id hoặc return_url." }, 400);
    }

    const { data: invoice, error: invoiceError } = await callerClient
        .from("invoices")
        .select("invoice_id, invoice_code, total_amount, status")
        .eq("invoice_id", invoiceId)
        .single();

    if (invoiceError || !invoice) {
        return jsonResponse({ error: "Không tìm thấy hóa đơn hoặc bạn không có quyền truy cập." }, 404);
    }
    if (invoice.status === "Đã thanh toán") {
        return jsonResponse({ error: "Hóa đơn này đã được thanh toán." }, 400);
    }
    if (!invoice.total_amount || invoice.total_amount <= 0) {
        return jsonResponse({ error: "Số tiền hóa đơn không hợp lệ." }, 400);
    }

    // Số tiền LUÔN lấy từ invoice trong DB — không bao giờ tin số tiền do
    // client gửi lên, để không ai có thể tự đổi số tiền thanh toán.
    const amount = Math.round(invoice.total_amount);
    const txnRef = `${invoice.invoice_code}-${Date.now()}`;
    const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "127.0.0.1";
    const now = new Date();
    const expire = new Date(now.getTime() + 15 * 60 * 1000); // link hết hạn sau 15 phút

    const vnpParams: Record<string, string> = {
        vnp_Version: VNPAY_VERSION,
        vnp_Command: "pay",
        vnp_TmnCode: VNPAY_TMN_CODE,
        vnp_Amount: String(amount * 100), // VNPay yêu cầu nhân 100 (không có phần thập phân)
        vnp_CurrCode: "VND",
        vnp_TxnRef: txnRef,
        vnp_OrderInfo: `Thanh toan hoa don ${invoice.invoice_code}`,
        vnp_OrderType: "other",
        vnp_Locale: "vn",
        vnp_ReturnUrl: returnUrl,
        vnp_IpAddr: clientIp,
        vnp_CreateDate: formatVnpDate(now),
        vnp_ExpireDate: formatVnpDate(expire),
    };

    const secureHash = await computeSecureHash(vnpParams);

    // Chuỗi ký (raw hoặc đã encode tùy thuật toán) chỉ dùng để tính chữ ký;
    // URL thực tế gửi cho VNPay luôn phải encode chuẩn để trình duyệt/HTTP
    // hiểu đúng — VNPay sẽ decode lại về đúng giá trị gốc trước khi so khớp.
    const query = Object.keys(vnpParams)
        .sort()
        .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(vnpParams[k]).replace(/%20/g, "+")}`)
        .join("&");
    const paymentUrl = `${VNPAY_PAY_URL}?${query}&vnp_SecureHash=${secureHash}`;

    // Log tạm để chẩn đoán lỗi "Sai chữ ký" — KHÔNG log VNPAY_HASH_SECRET.
    // vnp_TmnCode không phải bí mật (nó nằm công khai ngay trên URL thanh
    // toán), nên log để đối chiếu là an toàn.
    console.log("[vnpay-create-payment] hashType:", VNPAY_HASH_TYPE, "| version:", VNPAY_VERSION);
    console.log("[vnpay-create-payment] tmnCode:", VNPAY_TMN_CODE, "| tmnCode length:", VNPAY_TMN_CODE.length);
    console.log("[vnpay-create-payment] hashSecret length:", VNPAY_HASH_SECRET.length);
    console.log("[vnpay-create-payment] secureHash:", secureHash);
    console.log("[vnpay-create-payment] paymentUrl:", paymentUrl);

    // Ghi trước một dòng "Chờ xác nhận" để vnpay-ipn có transaction_ref mà
    // đối chiếu khi VNPay gọi về. Policy payments_insert hiện có đã cho phép
    // family tự tạo dòng ở đúng trạng thái này.
    // Lưu kèm vnp_CreateDate gốc trong "note" (dạng máy đọc được) vì API
    // querydr (vnpay-query-status) bắt buộc phải có đúng giá trị này để tra
    // cứu lại giao dịch — không có cách nào lấy lại được nếu không lưu từ đầu.
    const { error: insertError } = await callerClient.from("payments").insert({
        invoice_id: invoiceId,
        amount,
        method: "VNPay",
        status: "Chờ xác nhận",
        transaction_ref: txnRef,
        paid_by: callerUser.user.id,
        note: `vnp_createdate=${vnpParams.vnp_CreateDate}`,
    });

    if (insertError) {
        return jsonResponse({ error: "Không thể tạo giao dịch: " + insertError.message }, 400);
    }

    return jsonResponse({ paymentUrl, txnRef }, 200);
});
