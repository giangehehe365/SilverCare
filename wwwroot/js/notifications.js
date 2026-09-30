// Thông báo trong ứng dụng: popup góc màn hình + chuông thông báo trên topbar.
// Dữ liệu nằm ở bảng public.notifications, do trigger phía Postgres tạo ra
// (hóa đơn, thanh toán, lịch chăm sóc, cảnh báo sức khỏe — xem mục 9d trong
// supabase/schema.sql). Thông báo mới tới qua Supabase Realtime; có thêm
// polling định kỳ để không sót khi Realtime mất kết nối.
(function () {
    var POLL_INTERVAL_MS = 60 * 1000;
    var SCHEDULER_INTERVAL_MS = 2 * 60 * 1000;
    var TOAST_DURATION_MS = 8000;
    var MAX_TOASTS = 4;
    var LIST_LIMIT = 20;

    var TYPE_META = {
        billing: {
            label: "Thanh toán",
            url: "/Home/Billing",
            color: "#7a5af8",
            bg: "#f4f3ff",
            icon: '<svg viewBox="0 0 24 24"><path d="M21 12V7H5a2 2 0 0 1 0-4h14v4"/><path d="M3 5v14a2 2 0 0 0 2 2h16v-5"/><path d="M18 12a2 2 0 0 0 0 4h4v-4Z"/></svg>'
        },
        schedule: {
            label: "Lịch chăm sóc",
            url: "/Home/Schedule",
            color: "#0ba5ec",
            bg: "#f0f9ff",
            icon: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>'
        },
        health: {
            label: "Sức khỏe",
            url: "/Home/Notifications?tab=alerts",
            color: "#f04438",
            bg: "#fef3f2",
            icon: '<svg viewBox="0 0 24 24"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>'
        },
        other: {
            label: "Thông báo",
            url: null,
            color: "#667085",
            bg: "#f2f4f7",
            icon: '<svg viewBox="0 0 24 24"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>'
        }
    };

    var user = null;
    var knownIds = {};
    var lastSeenId = 0;
    var unreadCount = 0;
    var items = [];
    var started = false;

    var bellBtn, countEl, panel, listEl, markAllBtn, toastStack;

    function meta(type) {
        return TYPE_META[type] || TYPE_META.other;
    }

    function escapeHtml(str) {
        var div = document.createElement("div");
        div.textContent = str == null ? "" : String(str);
        return div.innerHTML;
    }

    function timeAgo(iso) {
        var diff = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
        if (diff < 60) return "Vừa xong";
        if (diff < 3600) return Math.floor(diff / 60) + " phút trước";
        if (diff < 86400) return Math.floor(diff / 3600) + " giờ trước";
        if (diff < 7 * 86400) return Math.floor(diff / 86400) + " ngày trước";
        var d = new Date(iso);
        return ("0" + d.getDate()).slice(-2) + "/" + ("0" + (d.getMonth() + 1)).slice(-2) + "/" + d.getFullYear();
    }

    // id lớn nhất đã hiện popup — lưu theo tài khoản để chuyển trang không hiện lại
    function storageKey() {
        return "silvercare_notif_last_popped_" + user.id;
    }

    function readLastPopped() {
        try {
            return parseInt(localStorage.getItem(storageKey()), 10) || 0;
        } catch (e) {
            return 0;
        }
    }

    function writeLastPopped(id) {
        try {
            if (id > readLastPopped()) localStorage.setItem(storageKey(), String(id));
        } catch (e) { /* bỏ qua: trình duyệt chặn storage */ }
    }

    // ---------- Badge ----------
    function renderBadge() {
        if (!countEl) return;
        if (unreadCount > 0) {
            countEl.textContent = unreadCount > 99 ? "99+" : String(unreadCount);
            countEl.hidden = false;
            bellBtn.setAttribute("aria-label", "Thông báo (" + unreadCount + " chưa đọc)");
        } else {
            countEl.hidden = true;
            bellBtn.setAttribute("aria-label", "Thông báo");
        }
    }

    async function refreshUnreadCount() {
        var res = await window.sb
            .from("notifications")
            .select("notification_id", { count: "exact", head: true })
            .eq("profile_id", user.id)
            .eq("is_read", false);
        if (!res.error) {
            unreadCount = res.count || 0;
            renderBadge();
        }
    }

    // ---------- Popup (toast) ----------
    function dismissToast(el) {
        if (!el || el.dataset.leaving) return;
        el.dataset.leaving = "1";
        el.classList.remove("show");
        setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 250);
    }

    function showToast(n) {
        if (!toastStack) return;
        var m = meta(n.notification_type);

        var el = document.createElement("div");
        el.className = "notif-toast";
        el.setAttribute("role", "status");
        el.style.setProperty("--notif-accent", m.color);
        el.innerHTML =
            '<div class="notif-toast-icon" style="color:' + m.color + ";background:" + m.bg + '">' + m.icon + "</div>" +
            '<div class="notif-toast-body">' +
                '<div class="notif-toast-title">' + escapeHtml(n.title) + "</div>" +
                '<div class="notif-toast-message">' + escapeHtml(n.message) + "</div>" +
                '<div class="notif-toast-meta">' + escapeHtml(m.label) + " · " + timeAgo(n.created_at) + "</div>" +
            "</div>" +
            '<button type="button" class="notif-toast-close" aria-label="Đóng">&times;</button>';

        var timer = null;
        function startTimer() { timer = setTimeout(function () { dismissToast(el); }, TOAST_DURATION_MS); }
        el.addEventListener("mouseenter", function () { clearTimeout(timer); });
        el.addEventListener("mouseleave", startTimer);

        el.querySelector(".notif-toast-close").addEventListener("click", function (e) {
            e.stopPropagation();
            dismissToast(el);
        });
        el.addEventListener("click", function () {
            dismissToast(el);
            openNotification(n);
        });

        toastStack.appendChild(el);
        var live = toastStack.querySelectorAll(".notif-toast:not([data-leaving])");
        if (live.length > MAX_TOASTS) dismissToast(live[0]);

        requestAnimationFrame(function () { el.classList.add("show"); });
        startTimer();
    }

    // ---------- Danh sách trong chuông ----------
    function renderList() {
        if (!listEl) return;
        if (items.length === 0) {
            listEl.innerHTML = '<div class="notif-empty">Chưa có thông báo nào.</div>';
            return;
        }
        listEl.innerHTML = items.map(function (n) {
            var m = meta(n.notification_type);
            return '<button type="button" class="notif-item' + (n.is_read ? "" : " unread") + '" data-id="' + n.notification_id + '">' +
                '<span class="notif-item-icon" style="color:' + m.color + ";background:" + m.bg + '">' + m.icon + "</span>" +
                '<span class="notif-item-body">' +
                    '<span class="notif-item-title">' + escapeHtml(n.title) + "</span>" +
                    '<span class="notif-item-message">' + escapeHtml(n.message) + "</span>" +
                    '<span class="notif-item-meta">' + escapeHtml(m.label) + " · " + timeAgo(n.created_at) + "</span>" +
                "</span>" +
            "</button>";
        }).join("");
    }

    async function loadList() {
        var res = await window.sb
            .from("notifications")
            .select("notification_id, notification_type, title, message, is_read, created_at, resident_id")
            .eq("profile_id", user.id)
            .order("created_at", { ascending: false })
            .limit(LIST_LIMIT);
        if (res.error) {
            listEl.innerHTML = '<div class="notif-empty">Không tải được thông báo.</div>';
            return;
        }
        items = res.data || [];
        items.forEach(function (n) { knownIds[n.notification_id] = true; });
        renderList();
    }

    async function markRead(ids) {
        if (!ids.length) return;
        var res = await window.sb
            .from("notifications")
            .update({ is_read: true, read_at: new Date().toISOString() })
            .in("notification_id", ids)
            .eq("profile_id", user.id);
        if (res.error) {
            console.error(res.error);
            return;
        }
        items.forEach(function (n) { if (ids.indexOf(n.notification_id) !== -1) n.is_read = true; });
        renderList();
        refreshUnreadCount();
        document.dispatchEvent(new CustomEvent("silvercare:notifications-read", { detail: { ids: ids } }));
    }

    async function openNotification(n) {
        if (!n.is_read) await markRead([n.notification_id]);
        var url = meta(n.notification_type).url;
        if (url && (window.location.pathname + window.location.search).toLowerCase() !== url.toLowerCase()) {
            window.location.href = url;
        }
    }

    function togglePanel(open) {
        var willOpen = typeof open === "boolean" ? open : panel.hidden;
        panel.hidden = !willOpen;
        bellBtn.setAttribute("aria-expanded", willOpen ? "true" : "false");
        if (willOpen) {
            listEl.innerHTML = '<div class="notif-empty">Đang tải...</div>';
            loadList();
        }
    }

    // ---------- Nhận thông báo mới ----------
    function handleIncoming(n) {
        if (!n || knownIds[n.notification_id] || n.profile_id && n.profile_id !== user.id) return;
        knownIds[n.notification_id] = true;
        lastSeenId = Math.max(lastSeenId, n.notification_id);
        writeLastPopped(n.notification_id);

        if (!n.is_read) {
            unreadCount++;
            renderBadge();
            showToast(n);
        }
        // Trang "Cảnh báo & Thông báo" nghe sự kiện này để thêm dòng mới ngay
        document.dispatchEvent(new CustomEvent("silvercare:notification", { detail: n }));
        if (!panel.hidden) {
            items.unshift(n);
            items = items.slice(0, LIST_LIMIT);
            renderList();
        }
    }

    async function pollNew() {
        var res = await window.sb
            .from("notifications")
            .select("notification_id, profile_id, notification_type, title, message, is_read, created_at")
            .eq("profile_id", user.id)
            .gt("notification_id", lastSeenId)
            .order("notification_id", { ascending: true })
            .limit(10);
        if (res.error) return;
        (res.data || []).forEach(handleIncoming);
    }

    // Lần đầu vào trang: hiện popup cho các thông báo chưa đọc chưa từng hiện
    // (vd. tới trong lúc đang chuyển trang), tối đa 3 cái, trong 24 giờ qua.
    async function showMissed() {
        var lastPopped = readLastPopped();
        var since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
        var res = await window.sb
            .from("notifications")
            .select("notification_id, notification_type, title, message, is_read, created_at")
            .eq("profile_id", user.id)
            .order("notification_id", { ascending: false })
            .limit(LIST_LIMIT);
        if (res.error) return;

        var rows = res.data || [];
        rows.forEach(function (n) { knownIds[n.notification_id] = true; });
        lastSeenId = rows.length ? rows[0].notification_id : 0;

        rows
            .filter(function (n) { return !n.is_read && n.notification_id > lastPopped && n.created_at >= since; })
            .slice(0, 3)
            .reverse()
            .forEach(showToast);

        if (lastSeenId) writeLastPopped(lastSeenId);
    }

    function subscribeRealtime() {
        window.sb
            .channel("notifications-" + user.id)
            .on("postgres_changes", {
                event: "INSERT",
                schema: "public",
                table: "notifications",
                filter: "profile_id=eq." + user.id
            }, function (payload) {
                handleIncoming(payload.new);
            })
            .subscribe();
    }

    // Dự phòng khi project chưa bật pg_cron: nhắc lịch sắp đến giờ / trễ / hóa đơn quá hạn
    function runScheduler() {
        window.sb.rpc("process_scheduled_notifications").then(function (res) {
            if (res.error) console.warn("[SilverCare] process_scheduled_notifications:", res.error.message);
        });
    }

    async function start(currentUser) {
        if (started || !currentUser || !window.sb) return;
        started = true;
        user = currentUser;

        bellBtn = document.getElementById("notifBellBtn");
        countEl = document.getElementById("notifBellCount");
        panel = document.getElementById("notifPanel");
        listEl = document.getElementById("notifList");
        markAllBtn = document.getElementById("notifMarkAll");
        toastStack = document.getElementById("notifToastStack");
        if (!bellBtn || !panel) return;

        bellBtn.addEventListener("click", function (e) {
            e.stopPropagation();
            togglePanel();
        });
        document.addEventListener("click", function (e) {
            if (!panel.hidden && !panel.contains(e.target)) togglePanel(false);
        });
        document.addEventListener("keydown", function (e) {
            if (e.key === "Escape" && !panel.hidden) togglePanel(false);
        });
        listEl.addEventListener("click", function (e) {
            var btn = e.target.closest(".notif-item");
            if (!btn) return;
            var id = parseInt(btn.getAttribute("data-id"), 10);
            var n = items.find(function (x) { return x.notification_id === id; });
            if (n) openNotification(n);
        });
        markAllBtn.addEventListener("click", async function (e) {
            e.stopPropagation();
            var res = await window.sb
                .from("notifications")
                .update({ is_read: true, read_at: new Date().toISOString() })
                .eq("profile_id", user.id)
                .eq("is_read", false);
            if (res.error) {
                console.error(res.error);
                return;
            }
            items.forEach(function (n) { n.is_read = true; });
            renderList();
            refreshUnreadCount();
            document.dispatchEvent(new CustomEvent("silvercare:notifications-read", { detail: { ids: null } }));
        });

        await Promise.all([refreshUnreadCount(), showMissed()]);
        subscribeRealtime();
        setInterval(pollNew, POLL_INTERVAL_MS);

        runScheduler();
        setInterval(runScheduler, SCHEDULER_INTERVAL_MS);
    }

    window.SilverCareNotifications = {
        refreshUnreadCount: function () { if (user) refreshUnreadCount(); }
    };

    document.addEventListener("silvercare:auth-ready", function (e) { start(e.detail); });
    if (window.currentUser) start(window.currentUser);
})();
