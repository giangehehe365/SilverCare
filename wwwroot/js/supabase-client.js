// Khởi tạo client Supabase dùng chung cho toàn bộ trang.
// URL và Anon Key được Razor layout bơm vào window.__SUPABASE_URL__ / __SUPABASE_ANON_KEY__
// từ appsettings.json (mục "Supabase"). Anon key được phép lộ ra trình duyệt —
// mọi phân quyền thật nằm ở Row Level Security trên Postgres, không phải ở khóa này.
(function () {
    var url = window.__SUPABASE_URL__;
    var anonKey = window.__SUPABASE_ANON_KEY__;

    if (!url || !anonKey || url.indexOf("YOUR-PROJECT-REF") !== -1) {
        console.warn(
            "[SilverCare] Chưa cấu hình Supabase. Cập nhật Supabase:Url và Supabase:AnonKey trong appsettings.json."
        );
    }

    window.sb = window.supabase.createClient(url, anonKey, {
        auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: false,
        },
    });
})();
