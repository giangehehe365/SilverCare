// Supabase Edge Function: vnpay-ipn
//
// Đây là "Instant Payment Notification" URL — VNPay (server của VNPay, KHÔNG
// phải trình duyệt người dùng) sẽ tự gọi GET vào URL này ngay sau khi người
// dùng hoàn tất/hủy thanh toán ở trang VNPay. Đây là nguồn xác nhận DUY NHẤT
// đáng tin cậy — không bao giờ đánh dấu thanh toán thành công dựa trên
// vnp_ReturnUrl phía trình duyệt, vì tham số trên URL trình duyệt có thể bị
// người dùng tự sửa tay.
//
// Function này KHÔNG có JWT của Supabase (VNPay không biết gì về Supabase
// Auth) — phải deploy với cờ --no-verify-jwt, và tự xác thực bằng cách kiểm
// tra chữ ký HMAC-SHA512 mà VNPay đính kèm (vnp_SecureHash).
//
// Cấu hình VNPAY_HASH_SECRET phải trùng với secret dùng ở vnpay-create-payment.
//
// Triển khai:
//   supabase functions deploy vnpay-ipn --no-verify-jwt
//
// Sau khi deploy, lấy URL function (dạng
//   https://<project-ref>.functions.supabase.co/vnpay-ipn
// ) và khai báo vào ô "IPN URL" trong trang quản trị Merchant Sandbox VNPay.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHash } from "node:crypto";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VNPAY_HASH_SECRET = (Deno.env.get("VNPAY_HASH_SECRET") ?? "").trim();
// PHẢI khớp với VNPAY_HASH_TYPE đặt ở vnpay-create-payment — cả 2 chiều
// ký/xác minh phải dùng cùng 1 thuật toán mà Terminal VNPay đang cấu hình.
const VNPAY_HASH_TYPE = (Deno.env.get("VNPAY_HASH_TYPE") ?? "HMACSHA512").trim().toUpperCase();

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

// Terminal cũ (MD5): chỉ field "vnp_"/"user_" không rỗng, nối RAW "key=value"
// (giá trị đã được URLSearchParams tự giải mã, KHÔNG encode lại), rồi
// MD5(secretKey + chuỗi đó) — phải khớp chính xác cách vnpay-create-payment ký.
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

async function computeSecureHash(params: Record<string, string>): Promise<string> {
    if (VNPAY_HASH_TYPE === "MD5") {
        return md5Hex(VNPAY_HASH_SECRET + buildSignDataMd5(params));
    }
    return await hmacSHA512(VNPAY_HASH_SECRET, buildSignDataHmac(params));
}

// VNPay quy định response body PHẢI đúng định dạng này để họ biết đã nhận
// được IPN thành công (khác với việc thanh toán có thành công hay không) —
// nếu không trả đúng dạng, VNPay sẽ coi là lỗi và tự động gọi lại nhiều lần.
function ipnResponse(RspCode: string, Message: string): Response {
    return new Response(JSON.stringify({ RspCode, Message }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
    });
}

Deno.serve(async (req) => {
    if (!VNPAY_HASH_SECRET) {
        return ipnResponse("99", "IPN chưa được cấu hình VNPAY_HASH_SECRET");
    }

    const url = new URL(req.url);
    const received: Record<string, string> = {};
    for (const [k, v] of url.searchParams.entries()) received[k] = v;

    const secureHash = received["vnp_SecureHash"];
    delete received["vnp_SecureHash"];
    delete received["vnp_SecureHashType"];

    if (!secureHash) {
        return ipnResponse("97", "Invalid signature");
    }

    const computedHash = await computeSecureHash(received);

    if (computedHash.toLowerCase() !== secureHash.toLowerCase()) {
        console.log("[vnpay-ipn] hashType:", VNPAY_HASH_TYPE, "computed:", computedHash, "received:", secureHash);
        return ipnResponse("97", "Invalid signature");
    }

    const txnRef = received["vnp_TxnRef"];
    const vnpAmount = Number(received["vnp_Amount"] ?? "0") / 100;
    const responseCode = received["vnp_ResponseCode"];
    const transactionStatus = received["vnp_TransactionStatus"];

    if (!txnRef) {
        return ipnResponse("01", "Order not found");
    }

    // Bắt buộc dùng service_role ở đây: VNPay gọi thẳng vào server, không có
    // phiên đăng nhập Supabase nào để RLS bám vào — chữ ký HMAC vừa xác minh
    // ở trên chính là lớp xác thực thay thế cho JWT trong trường hợp này.
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: payment, error: findError } = await adminClient
        .from("payments")
        .select("payment_id, invoice_id, amount, status")
        .eq("transaction_ref", txnRef)
        .single();

    if (findError || !payment) {
        return ipnResponse("01", "Order not found");
    }

    if (payment.status !== "Chờ xác nhận") {
        // Đã xử lý trước đó (VNPay có thể gọi lại IPN nhiều lần) — báo thành
        // công để VNPay ngừng gọi lại, không xử lý thêm lần nữa.
        return ipnResponse("02", "Order already confirmed");
    }

    if (Math.round(vnpAmount) !== Math.round(payment.amount)) {
        return ipnResponse("04", "Invalid amount");
    }

    const isSuccess = responseCode === "00" && transactionStatus === "00";

    const { error: updateError } = await adminClient
        .from("payments")
        .update({
            status: isSuccess ? "Thành công" : "Thất bại",
            note: `VNPay responseCode=${responseCode} transactionStatus=${transactionStatus}`,
        })
        .eq("payment_id", payment.payment_id);

    if (updateError) {
        return ipnResponse("99", "Update failed: " + updateError.message);
    }

    return ipnResponse("00", "Confirm Success");
});
