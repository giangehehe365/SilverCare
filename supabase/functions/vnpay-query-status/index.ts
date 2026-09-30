// Supabase Edge Function: vnpay-query-status
//
// Fallback "đồng bộ trạng thái" — dùng khi IPN của VNPay không gọi về được
// (ví dụ IPN URL chưa lưu đúng ở trang quản trị VNPay). Thay vì ngồi chờ
// VNPay chủ động gọi tới, function này CHỦ ĐỘNG hỏi VNPay qua API "querydr"
// chính thức: "giao dịch TxnRef này hiện trạng thái gì?", rồi tự cập nhật lại
// payments/invoices — không cần đợi hạ tầng IPN hoạt động.
//
// Đây cũng là pattern khuyến nghị chuẩn khi tích hợp cổng thanh toán: IPN là
// đường nhanh, querydr là đường đối soát dự phòng cho các giao dịch bị kẹt.
//
// Cấu hình: dùng chung VNPAY_TMN_CODE / VNPAY_HASH_SECRET / VNPAY_HASH_TYPE
// với vnpay-create-payment.
//
// Triển khai:
//   supabase functions deploy vnpay-query-status
//
// Gọi từ client (người đã đăng nhập, phải có quyền xem payment đó theo RLS):
//   const { data } = await sb.functions.invoke('vnpay-query-status', { body: { transaction_ref } });

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHash } from "node:crypto";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VNPAY_TMN_CODE = (Deno.env.get("VNPAY_TMN_CODE") ?? "").trim();
const VNPAY_HASH_SECRET = (Deno.env.get("VNPAY_HASH_SECRET") ?? "").trim();
const VNPAY_HASH_TYPE = (Deno.env.get("VNPAY_HASH_TYPE") ?? "HMACSHA512").trim().toUpperCase();
const VNPAY_QUERY_URL = Deno.env.get("VNPAY_QUERY_URL") ?? "https://sandbox.vnpayment.vn/merchant_webapi/api/transaction";

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

function md5Hex(data: string): string {
    return createHash("md5").update(data, "utf-8").digest("hex");
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

async function computeQueryHash(data: string): Promise<string> {
    if (VNPAY_HASH_TYPE === "MD5") return md5Hex(VNPAY_HASH_SECRET + data);
    return await hmacSHA512(VNPAY_HASH_SECRET, data);
}

function pad(n: number): string {
    return n.toString().padStart(2, "0");
}
function formatVnpDate(d: Date): string {
    const vn = new Date(d.getTime() + 7 * 60 * 60 * 1000);
    return (
        vn.getUTCFullYear().toString() + pad(vn.getUTCMonth() + 1) + pad(vn.getUTCDate()) +
        pad(vn.getUTCHours()) + pad(vn.getUTCMinutes()) + pad(vn.getUTCSeconds())
    );
}

Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const authHeader = req.headers.get("Authorization") ?? "";
    const callerToken = authHeader.replace("Bearer ", "");
    if (!callerToken) return jsonResponse({ error: "Thiếu token xác thực." }, 401);

    // Đọc bằng client gắn JWT người gọi để RLS tự chặn: gia đình chỉ đồng bộ
    // được thanh toán của hóa đơn thuộc người thân mình.
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
        global: { headers: { Authorization: `Bearer ${callerToken}` } },
    });
    const { data: callerUser, error: userError } = await callerClient.auth.getUser();
    if (userError || !callerUser?.user) return jsonResponse({ error: "Token không hợp lệ." }, 401);

    let body: { transaction_ref?: string };
    try {
        body = await req.json();
    } catch {
        return jsonResponse({ error: "Payload không hợp lệ." }, 400);
    }
    const txnRef = body.transaction_ref;
    if (!txnRef) return jsonResponse({ error: "Thiếu transaction_ref." }, 400);

    const { data: payment, error: findError } = await callerClient
        .from("payments")
        .select("payment_id, invoice_id, amount, status, method, note, transaction_ref")
        .eq("transaction_ref", txnRef)
        .eq("method", "VNPay")
        .single();

    if (findError || !payment) {
        return jsonResponse({ error: "Không tìm thấy giao dịch hoặc bạn không có quyền xem." }, 404);
    }

    if (payment.status !== "Chờ xác nhận") {
        return jsonResponse({ status: payment.status, message: "Giao dịch đã được xử lý trước đó." }, 200);
    }

    const createDateMatch = /vnp_createdate=(\d{14})/.exec(payment.note ?? "");
    if (!createDateMatch) {
        return jsonResponse({ error: "Thiếu vnp_createdate gốc, không thể tra cứu (giao dịch tạo trước khi có tính năng này)." }, 400);
    }
    const transactionDate = createDateMatch[1];

    const requestId = `RQ${Date.now()}`;
    const version = "2.1.0";
    const command = "querydr";
    const createDate = formatVnpDate(new Date());
    const ipAddr = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "127.0.0.1";
    const orderInfo = `Truy van giao dich ${txnRef}`;

    // Định dạng ký RIÊNG của querydr: nối theo thứ tự CỐ ĐỊNH bằng "|" —
    // KHÁC với kiểu sort key=value&... dùng ở API pay/IPN.
    const signData = [requestId, version, command, VNPAY_TMN_CODE, txnRef, transactionDate, createDate, ipAddr, orderInfo].join("|");
    const secureHash = await computeQueryHash(signData);

    const vnpayRes = await fetch(VNPAY_QUERY_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            vnp_RequestId: requestId,
            vnp_Version: version,
            vnp_Command: command,
            vnp_TmnCode: VNPAY_TMN_CODE,
            vnp_TxnRef: txnRef,
            vnp_OrderInfo: orderInfo,
            vnp_TransactionDate: transactionDate,
            vnp_CreateDate: createDate,
            vnp_IpAddr: ipAddr,
            vnp_SecureHash: secureHash,
        }),
    });

    let vnpayData: Record<string, unknown>;
    try {
        vnpayData = await vnpayRes.json();
    } catch {
        return jsonResponse({ error: "VNPay trả về dữ liệu không hợp lệ." }, 502);
    }

    console.log("[vnpay-query-status] request:", signData);
    console.log("[vnpay-query-status] response:", JSON.stringify(vnpayData));

    const responseCode = String(vnpayData.vnp_ResponseCode ?? "");
    const transactionStatus = String(vnpayData.vnp_TransactionStatus ?? "");

    if (responseCode !== "00") {
        return jsonResponse({
            status: payment.status,
            message: `VNPay chưa trả lời được: ${vnpayData.vnp_Message ?? responseCode}`,
        }, 200);
    }

    // Service_role vì đây là kết quả lấy trực tiếp từ máy chủ VNPay qua kênh
    // HTTPS do server này chủ động gọi (không phải request công khai ai cũng
    // gọi được như IPN) — không cần RLS chặn thêm ở bước ghi.
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    if (transactionStatus === "00") {
        await adminClient.from("payments").update({
            status: "Thành công",
            note: `Đồng bộ thủ công từ VNPay querydr: ${vnpayData.vnp_Message ?? "success"}`,
        }).eq("payment_id", payment.payment_id);
        return jsonResponse({ status: "Thành công" }, 200);
    }

    if (["02", "09"].includes(transactionStatus)) {
        await adminClient.from("payments").update({
            status: "Thất bại",
            note: `Đồng bộ thủ công từ VNPay querydr: ${vnpayData.vnp_Message ?? transactionStatus}`,
        }).eq("payment_id", payment.payment_id);
        return jsonResponse({ status: "Thất bại" }, 200);
    }

    return jsonResponse({ status: "Chờ xác nhận", message: "VNPay vẫn đang xử lý giao dịch." }, 200);
});
