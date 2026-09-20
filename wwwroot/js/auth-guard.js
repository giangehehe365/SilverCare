// Bảo vệ các trang trong _DashboardLayout: xác thực Supabase phía client.
// Đây KHÔNG phải là lớp bảo mật thật (đó là việc của Row Level Security trong
// supabase/schema.sql) — auth-guard.js chỉ lo trải nghiệm: chuyển hướng đúng
// chỗ, hiện đúng tên/vai trò, ẩn menu không thuộc quyền.
(function () {
    var ROLE_LABELS = {
        admin: "Quản trị viên",
        manager: "Quản lý trung tâm",
        staff: "Nhân viên chăm sóc",
        family: "Người nhà",
    };

    function computeInitials(fullName) {
        if (!fullName) return "SC";
        var parts = fullName.trim().split(/\s+/);
        var letters;
        if (parts.length >= 3) {
            letters = [parts[0][0], parts[parts.length - 2][0], parts[parts.length - 1][0]];
        } else {
            letters = parts.map(function (p) { return p[0]; });
        }
        return letters.join("").toUpperCase().slice(0, 3);
    }

    function redirectToLogin() {
        window.location.replace("/");
    }

    function redirectToAccessDenied(featureName) {
        window.location.replace("/Home/AccessDenied?feature=" + encodeURIComponent(featureName || ""));
    }

    function applyRoleVisibility(role) {
        document.querySelectorAll("[data-roles]").forEach(function (el) {
            var allowed = el.getAttribute("data-roles").split(",").map(function (r) { return r.trim(); });
            if (allowed.indexOf(role) === -1) {
                el.style.display = "none";
            }
        });
    }

    function populateUserUi(user, profile) {
        var fullName = profile.full_name || user.email || "Người dùng";
        var role = profile.role || "staff";
        var initials = computeInitials(fullName);
        var roleLabel = ROLE_LABELS[role] || role;

        document.querySelectorAll("[data-user-fullname]").forEach(function (el) { el.textContent = fullName; });
        document.querySelectorAll("[data-user-initials]").forEach(function (el) { el.textContent = initials; });
        document.querySelectorAll("[data-user-role-label]").forEach(function (el) { el.textContent = roleLabel; });
    }

    async function init() {
        if (!window.sb) {
            console.error("[SilverCare] Supabase client chưa sẵn sàng.");
            return;
        }

        var appRoot = document.getElementById("app-root");

        var sessionResult = await window.sb.auth.getSession();
        var session = sessionResult.data && sessionResult.data.session;

        if (!session) {
            redirectToLogin();
            return;
        }

        var user = session.user;
        var profileResult = await window.sb
            .from("profiles")
            .select("full_name, role, phone, department, avatar_url, is_active")
            .eq("id", user.id)
            .single();

        if (profileResult.error || !profileResult.data || profileResult.data.is_active === false) {
            await window.sb.auth.signOut();
            redirectToLogin();
            return;
        }

        var profile = profileResult.data;

        window.currentUser = {
            id: user.id,
            email: user.email,
            fullName: profile.full_name,
            role: profile.role,
            phone: profile.phone,
            department: profile.department,
            avatarUrl: profile.avatar_url,
        };

        var allowedRolesMeta = document.querySelector('meta[name="allowed-roles"]');
        if (allowedRolesMeta && allowedRolesMeta.content) {
            var allowedRoles = allowedRolesMeta.content.split(",").map(function (r) { return r.trim(); });
            if (allowedRoles.indexOf(profile.role) === -1) {
                var featureMeta = document.querySelector('meta[name="feature-name"]');
                redirectToAccessDenied(featureMeta ? featureMeta.content : document.title);
                return;
            }
        }

        populateUserUi(user, profile);
        applyRoleVisibility(profile.role);

        if (appRoot) {
            appRoot.style.visibility = "visible";
        }

        document.dispatchEvent(new CustomEvent("silvercare:auth-ready", { detail: window.currentUser }));
    }

    document.addEventListener("DOMContentLoaded", function () {
        init();

        var logoutBtn = document.getElementById("logoutBtn");
        if (logoutBtn) {
            logoutBtn.addEventListener("click", async function (e) {
                e.preventDefault();
                try {
                    await window.sb.auth.signOut();
                } catch (err) {
                    console.error(err);
                }
                window.location.replace("/");
            });
        }
    });
})();
