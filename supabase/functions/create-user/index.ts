// Supabase Edge Function: create-user
// Cho phép Admin tạo tài khoản nhân viên/quản lý mới mà KHÔNG làm mất phiên
// đăng nhập hiện tại (gọi trực tiếp supabase.auth.signUp() từ client sẽ
// tự động đăng nhập sang tài khoản vừa tạo — đây là lý do việc này phải
// chạy phía server với service_role key).
//
// Triển khai:
//   supabase functions deploy create-user
//
// Gọi từ client (chỉ khi người gọi đã đăng nhập với role = 'admin'):
//   const { data, error } = await sb.functions.invoke('create-user', {
//     body: { email, password, full_name, role, phone, department }
//   });

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ALLOWED_ROLES = ["admin", "manager", "staff", "family"];

Deno.serve(async (req) => {
    if (req.method !== "POST") {
        return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const callerToken = authHeader.replace("Bearer ", "");
    if (!callerToken) {
        return jsonResponse({ error: "Thiếu token xác thực." }, 401);
    }

    // Client dùng service_role để có quyền admin, nhưng ta tự xác minh
    // người GỌI function này thực sự là admin trước khi làm gì khác.
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: callerUser, error: callerError } = await adminClient.auth.getUser(callerToken);
    if (callerError || !callerUser?.user) {
        return jsonResponse({ error: "Token không hợp lệ." }, 401);
    }

    const { data: callerProfile, error: profileError } = await adminClient
        .from("profiles")
        .select("role")
        .eq("id", callerUser.user.id)
        .single();

    if (profileError || callerProfile?.role !== "admin") {
        return jsonResponse({ error: "Chỉ Admin mới được tạo tài khoản mới." }, 403);
    }

    let body: {
        email?: string;
        password?: string;
        full_name?: string;
        role?: string;
        phone?: string;
        department?: string;
    };

    try {
        body = await req.json();
    } catch {
        return jsonResponse({ error: "Payload không hợp lệ." }, 400);
    }

    const { email, password, full_name, role, phone, department } = body;

    if (!email || !password || !full_name) {
        return jsonResponse({ error: "Thiếu email, mật khẩu hoặc họ tên." }, 400);
    }
    if (password.length < 6) {
        return jsonResponse({ error: "Mật khẩu phải có ít nhất 6 ký tự." }, 400);
    }
    const finalRole = ALLOWED_ROLES.includes(role ?? "") ? role! : "staff";

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name, role: finalRole },
    });

    if (createError || !created?.user) {
        return jsonResponse({ error: createError?.message ?? "Không thể tạo tài khoản." }, 400);
    }

    // Trigger public.handle_new_user() đã tạo dòng profiles mặc định,
    // cập nhật thêm phone/department nếu có.
    if (phone || department) {
        await adminClient
            .from("profiles")
            .update({ phone, department })
            .eq("id", created.user.id);
    }

    return jsonResponse({ user_id: created.user.id, email: created.user.email, role: finalRole }, 200);
});

function jsonResponse(body: unknown, status: number): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json" },
    });
}
