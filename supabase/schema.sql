/* =========================================================
   SILVERCARE — SUPABASE (POSTGRES) SCHEMA + RLS
   Chạy toàn bộ file này trong Supabase SQL Editor (project của bạn).
   An toàn khi chạy lại nhiều lần (idempotent) nhờ IF NOT EXISTS / OR REPLACE.
   ========================================================= */

create extension if not exists pgcrypto;

/* =========================================================
   1. PROFILES — mở rộng auth.users với vai trò nghiệp vụ
   ========================================================= */

create table if not exists public.profiles (
    id           uuid primary key references auth.users(id) on delete cascade,
    full_name    text not null,
    email        text,
    role         text not null default 'staff'
                 check (role in ('admin','manager','staff','family')),
    phone        text,
    department   text,
    avatar_url   text,
    is_active    boolean not null default true,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz
);

-- Hàm đọc vai trò của người dùng hiện tại (security definer để tránh đệ quy RLS)
create or replace function public.user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select role from public.profiles where id = auth.uid();
$$;

-- Tự tạo hồ sơ profiles khi có tài khoản auth.users mới
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, full_name, email, role)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
        new.email,
        coalesce(new.raw_user_meta_data->>'role', 'staff')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- Ngăn người dùng thường tự đổi role/is_active của chính mình
create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    -- auth.uid() chỉ khác NULL khi update chạy qua phiên đăng nhập thật của app
    -- (PostgREST/GoTrue). Khi chạy trực tiếp trong SQL Editor (vai trò postgres),
    -- auth.uid() luôn là NULL — đây là truy cập đã được tin cậy (cần đăng nhập
    -- Supabase Dashboard), nên bỏ qua giới hạn để Admin có thể tự cấp quyền
    -- cho tài khoản đầu tiên.
    if auth.uid() is not null and public.user_role() is distinct from 'admin' then
        new.role := old.role;
        new.is_active := old.is_active;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_protect_profile_fields on public.profiles;
create trigger trg_protect_profile_fields
    before update on public.profiles
    for each row execute function public.protect_profile_fields();


/* =========================================================
   2. ROOMS
   ========================================================= */

create table if not exists public.rooms (
    room_id       bigint generated always as identity primary key,
    room_code     text not null unique,
    room_name     text,
    floor_number  int,
    capacity      int not null default 1 check (capacity > 0),
    description   text,
    is_active     boolean not null default true,
    created_at    timestamptz not null default now()
);


/* =========================================================
   3. RESIDENTS
   ========================================================= */

create table if not exists public.residents (
    resident_id      bigint generated always as identity primary key,
    resident_code    text not null unique,
    full_name        text not null,
    date_of_birth    date,
    age              int check (age is null or age between 0 and 150),
    gender           text,
    room_id          bigint references public.rooms(room_id),
    blood_type       text,
    status           text not null default 'Đang ổn định',
    admission_date   date,
    medical_history  text,
    allergies        text,
    notes            text,
    is_active        boolean not null default true,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz
);

create or replace function public.generate_resident_code()
returns trigger
language plpgsql
as $$
declare
    next_num int;
begin
    if new.resident_code is null or new.resident_code = '' then
        select coalesce(max(substring(resident_code from 4)::int), 0) + 1
          into next_num
          from public.residents
         where resident_code ~ '^NCT[0-9]+$';
        new.resident_code := 'NCT' || lpad(next_num::text, 3, '0');
    end if;
    return new;
end;
$$;

drop trigger if exists trg_generate_resident_code on public.residents;
create trigger trg_generate_resident_code
    before insert on public.residents
    for each row execute function public.generate_resident_code();

create index if not exists ix_residents_room_id on public.residents(room_id);


/* =========================================================
   4. FAMILY MEMBERS
   ========================================================= */

create table if not exists public.family_members (
    family_member_id   bigint generated always as identity primary key,
    resident_id        bigint not null references public.residents(resident_id) on delete cascade,
    profile_id         uuid references public.profiles(id) on delete set null,
    full_name          text not null,
    relationship       text,
    phone              text,
    email              text,
    address            text,
    is_primary_contact boolean not null default false,
    is_active          boolean not null default true,
    created_at         timestamptz not null default now()
);

create index if not exists ix_family_members_resident_id on public.family_members(resident_id);
create index if not exists ix_family_members_profile_id on public.family_members(profile_id);


/* =========================================================
   5. HEALTH RECORDS
   ========================================================= */

create table if not exists public.health_records (
    health_record_id   bigint generated always as identity primary key,
    resident_id        bigint not null references public.residents(resident_id) on delete cascade,
    recorded_by        uuid references public.profiles(id),
    recorded_at        timestamptz not null default now(),
    systolic           int,
    diastolic          int,
    heart_rate         int,
    temperature        numeric(4,1),
    oxygen_saturation  numeric(5,2),
    weight             numeric(6,2),
    blood_sugar        numeric(6,2),
    health_status      text,
    note               text
);

create index if not exists ix_health_records_resident_id on public.health_records(resident_id);
create index if not exists ix_health_records_recorded_at on public.health_records(recorded_at);


/* =========================================================
   6. HEALTH ALERTS + RESOLUTIONS
   ========================================================= */

create table if not exists public.health_alerts (
    alert_id           bigint generated always as identity primary key,
    resident_id        bigint not null references public.residents(resident_id) on delete cascade,
    health_record_id   bigint references public.health_records(health_record_id),
    alert_type         text not null,
    severity           text not null default 'Thấp',
    title              text not null,
    message            text,
    trigger_value      text,
    ai_recommendation  text,
    status             text not null default 'Chưa xử lý',
    created_at         timestamptz not null default now(),
    resolved_at        timestamptz
);

create index if not exists ix_health_alerts_resident_id on public.health_alerts(resident_id);
create index if not exists ix_health_alerts_status on public.health_alerts(status);

create table if not exists public.alert_resolutions (
    resolution_id    bigint generated always as identity primary key,
    alert_id         bigint not null references public.health_alerts(alert_id) on delete cascade,
    resolved_by      uuid references public.profiles(id),
    resolution_type  text,
    action_taken     text,
    note             text,
    resolved_at      timestamptz not null default now()
);

-- Tự động tạo health_alerts khi một health_records mới vượt ngưỡng an toàn.
-- Ngưỡng khớp với logic severity phía UI (Health.cshtml) để không lệch pha.
create or replace function public.evaluate_health_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    bp_diff int;
    sev     text;
begin
    if new.systolic is null or new.diastolic is null or new.heart_rate is null or new.temperature is null then
        return new;
    end if;

    bp_diff := new.systolic - new.diastolic;

    if new.systolic >= 140 or new.diastolic >= 90 or bp_diff <= 20
       or new.heart_rate > 100 or new.heart_rate < 50
       or new.temperature >= 38.5 or new.temperature < 35.0
       or (new.oxygen_saturation is not null and new.oxygen_saturation < 92) then
        sev := 'Cao';
    elsif (new.systolic between 120 and 139) or (new.diastolic between 80 and 89)
       or (new.heart_rate between 91 and 100) or (new.heart_rate between 50 and 59)
       or (new.temperature between 37.5 and 38.4) then
        sev := 'Trung bình';
    else
        sev := null;
    end if;

    if sev is not null then
        declare
            recommendation text := '';
        begin
            if new.systolic >= 160 or new.diastolic >= 100 then
                recommendation := recommendation || 'Huyết áp tăng cao độ 2. Kiểm tra lại sau 30 phút nghỉ ngơi, nhắc uống thuốc hạ áp theo đơn, hạn chế muối. ';
            elsif new.systolic >= 140 or new.diastolic >= 90 then
                recommendation := recommendation || 'Huyết áp cao. Theo dõi thêm, nhắc người bệnh nghỉ ngơi và dùng thuốc đúng giờ. ';
            elsif (new.systolic < 90 and new.systolic > 0) or (new.diastolic < 60 and new.diastolic > 0) then
                recommendation := recommendation || 'Huyết áp thấp. Cho người bệnh nằm nghỉ, kê chân cao, theo dõi dấu hiệu chóng mặt/ngất. ';
            end if;

            if new.heart_rate > 100 then
                recommendation := recommendation || 'Nhịp tim nhanh bất thường, cần theo dõi sát và báo bác sĩ nếu kéo dài. ';
            elsif new.heart_rate < 50 then
                recommendation := recommendation || 'Nhịp tim chậm bất thường, cần theo dõi sát và báo bác sĩ nếu kéo dài. ';
            end if;

            if new.temperature >= 38.5 then
                recommendation := recommendation || 'Sốt cao, cần lau mát, bù nước điện giải và theo dõi nhiệt độ mỗi giờ. ';
            elsif new.temperature < 35.0 then
                recommendation := recommendation || 'Thân nhiệt thấp bất thường, cần giữ ấm và theo dõi sát. ';
            end if;

            if new.oxygen_saturation is not null and new.oxygen_saturation < 92 then
                recommendation := recommendation || 'SpO2 thấp, cần kiểm tra hô hấp và báo bác sĩ ngay. ';
            end if;

            if recommendation = '' then
                recommendation := 'Chỉ số nằm trong vùng cần theo dõi thêm, chưa ở mức nguy hiểm.';
            end if;

            insert into public.health_alerts
                (resident_id, health_record_id, alert_type, severity, title, message, trigger_value, ai_recommendation, status)
            values
            (
                new.resident_id,
                new.health_record_id,
                'Sinh hiệu bất thường',
                sev,
                'Chỉ số bất thường: ' || new.systolic || '/' || new.diastolic || ' mmHg, '
                    || new.heart_rate || ' bpm, ' || new.temperature || '°C',
                'Hệ thống phát hiện chỉ số sinh hiệu vượt ngưỡng an toàn, cần nhân viên kiểm tra.',
                new.systolic || '/' || new.diastolic || ' mmHg',
                trim(recommendation),
                'Chưa xử lý'
            );
        end;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_evaluate_health_alert on public.health_records;
create trigger trg_evaluate_health_alert
    after insert on public.health_records
    for each row execute function public.evaluate_health_alert();


/* =========================================================
   7. MEDICINES / SCHEDULES / ADMINISTRATIONS
   ========================================================= */

create table if not exists public.medicines (
    medicine_id    bigint generated always as identity primary key,
    medicine_name  text not null,
    generic_name   text,
    description    text,
    manufacturer   text,
    is_active      boolean not null default true,
    created_at     timestamptz not null default now()
);

create table if not exists public.medication_schedules (
    medication_schedule_id  bigint generated always as identity primary key,
    resident_id             bigint not null references public.residents(resident_id) on delete cascade,
    medicine_id             bigint not null references public.medicines(medicine_id),
    prescribed_by           uuid references public.profiles(id),
    dosage                  text not null,
    frequency               text,
    start_date              date not null,
    end_date                date,
    administration_time     time not null,
    instructions            text,
    status                  text not null default 'Đang sử dụng',
    created_at              timestamptz not null default now()
);

create table if not exists public.medication_administrations (
    administration_id       bigint generated always as identity primary key,
    medication_schedule_id  bigint not null references public.medication_schedules(medication_schedule_id) on delete cascade,
    administered_by         uuid references public.profiles(id),
    scheduled_date          date not null,
    scheduled_time          time not null,
    actual_time             time,
    status                  text not null default 'Chưa thực hiện',
    note                    text,
    created_at              timestamptz not null default now()
);


/* =========================================================
   8. CARE SCHEDULES
   ========================================================= */

create table if not exists public.care_schedules (
    care_schedule_id   bigint generated always as identity primary key,
    resident_id        bigint not null references public.residents(resident_id) on delete cascade,
    assigned_staff_id  uuid references public.profiles(id),
    schedule_name      text not null,
    schedule_date      date not null,
    start_time         time not null,
    end_time           time,
    schedule_type      text not null,
    status             text not null default 'Chưa thực hiện',
    note               text,
    created_at         timestamptz not null default now(),
    updated_at         timestamptz
);

create index if not exists ix_care_schedules_date on public.care_schedules(schedule_date);
create index if not exists ix_care_schedules_resident_id on public.care_schedules(resident_id);


/* =========================================================
   9. NOTIFICATIONS
   ========================================================= */

create table if not exists public.notifications (
    notification_id    bigint generated always as identity primary key,
    profile_id         uuid not null references public.profiles(id) on delete cascade,
    resident_id        bigint references public.residents(resident_id),
    notification_type  text,
    title              text not null,
    message            text not null,
    is_read            boolean not null default false,
    created_at         timestamptz not null default now(),
    read_at            timestamptz
);

create table if not exists public.notification_settings (
    notification_setting_id  bigint generated always as identity primary key,
    profile_id               uuid not null unique references public.profiles(id) on delete cascade,
    enable_health_alerts     boolean not null default true,
    enable_schedule_alerts   boolean not null default true,
    enable_medication_alerts boolean not null default true,
    enable_system_alerts     boolean not null default true,
    enable_email             boolean not null default false,
    updated_at               timestamptz not null default now()
);


/* =========================================================
   9b. APP SETTINGS (cấu hình chung — trang SystemSettings)
   ========================================================= */

create table if not exists public.app_settings (
    id                  int primary key default 1 check (id = 1),
    org_name            text not null default 'SilverCare',
    org_address         text,
    org_hotline         text,
    bank_name           text,
    bank_account_no     text,
    bank_account_holder text,
    updated_at          timestamptz not null default now()
);

insert into public.app_settings (id) values (1)
on conflict (id) do nothing;

alter table public.app_settings
    add column if not exists bank_name text,
    add column if not exists bank_account_no text,
    add column if not exists bank_account_holder text;


/* =========================================================
   9c. THANH TOÁN & VIỆN PHÍ (service_packages / invoices / payments)
   ========================================================= */

create table if not exists public.service_packages (
    service_package_id  bigint generated always as identity primary key,
    name                text not null,
    description         text,
    monthly_price       numeric(14,0) not null default 0,
    is_active           boolean not null default true,
    created_at          timestamptz not null default now()
);

create table if not exists public.resident_service_packages (
    resident_service_package_id bigint generated always as identity primary key,
    resident_id         bigint not null references public.residents(resident_id) on delete cascade,
    service_package_id  bigint not null references public.service_packages(service_package_id),
    start_date          date not null default current_date,
    end_date            date,
    created_at          timestamptz not null default now()
);

create index if not exists ix_resident_service_packages_resident_id on public.resident_service_packages(resident_id);

-- Mỗi cư dân chỉ được có TỐI ĐA 1 gói dịch vụ đang active (end_date is null)
-- tại một thời điểm — tránh lặp lại lỗi nhiều nơi cùng "gán gói" chỉ insert
-- mà không đóng gói cũ, dẫn đến không xác định được đâu mới là gói thật sự
-- đang áp dụng.
create unique index if not exists ux_resident_active_package
    on public.resident_service_packages (resident_id)
    where end_date is null;

create table if not exists public.invoices (
    invoice_id      bigint generated always as identity primary key,
    resident_id     bigint not null references public.residents(resident_id) on delete cascade,
    invoice_code    text unique,
    billing_month   int not null check (billing_month between 1 and 12),
    billing_year    int not null check (billing_year between 2020 and 2100),
    issue_date      date not null default current_date,
    due_date        date,
    total_amount    numeric(14,0) not null default 0,
    status          text not null default 'Chưa thanh toán'
                    check (status in ('Chưa thanh toán','Đã thanh toán','Quá hạn','Đã hủy')),
    note            text,
    created_by      uuid references public.profiles(id),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz
);

create index if not exists ix_invoices_resident_id on public.invoices(resident_id);
create index if not exists ix_invoices_status on public.invoices(status);

-- Tự sinh mã hóa đơn dạng HD-YYYY-MM-0001
create or replace function public.generate_invoice_code()
returns trigger
language plpgsql
as $$
declare
    next_num int;
    prefix   text;
begin
    if new.invoice_code is null or new.invoice_code = '' then
        prefix := 'HD-' || new.billing_year || '-' || lpad(new.billing_month::text, 2, '0');
        select coalesce(max(substring(invoice_code from '[0-9]+$')::int), 0) + 1
          into next_num
          from public.invoices
         where invoice_code like (prefix || '-%');
        new.invoice_code := prefix || '-' || lpad(next_num::text, 4, '0');
    end if;
    return new;
end;
$$;

drop trigger if exists trg_generate_invoice_code on public.invoices;
create trigger trg_generate_invoice_code
    before insert on public.invoices
    for each row execute function public.generate_invoice_code();

create table if not exists public.invoice_items (
    invoice_item_id  bigint generated always as identity primary key,
    invoice_id       bigint not null references public.invoices(invoice_id) on delete cascade,
    description      text not null,
    quantity         numeric(10,2) not null default 1,
    unit_price       numeric(14,0) not null default 0,
    amount           numeric(14,0) not null default 0
);

create index if not exists ix_invoice_items_invoice_id on public.invoice_items(invoice_id);

-- Tổng tiền hóa đơn luôn được tính lại tự động từ các dòng mục — không cho
-- phép lệch giữa invoices.total_amount và tổng invoice_items.
create or replace function public.sync_invoice_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    target_invoice_id bigint;
    new_total numeric(14,0);
begin
    target_invoice_id := coalesce(new.invoice_id, old.invoice_id);
    select coalesce(sum(amount), 0) into new_total from public.invoice_items where invoice_id = target_invoice_id;
    update public.invoices set total_amount = new_total, updated_at = now() where invoice_id = target_invoice_id;
    return new;
end;
$$;

drop trigger if exists trg_sync_invoice_total on public.invoice_items;
create trigger trg_sync_invoice_total
    after insert or update or delete on public.invoice_items
    for each row execute function public.sync_invoice_total();

create table if not exists public.payments (
    payment_id      bigint generated always as identity primary key,
    invoice_id      bigint not null references public.invoices(invoice_id) on delete cascade,
    amount          numeric(14,0) not null,
    method          text not null default 'Tiền mặt'
                    check (method in ('Tiền mặt','Chuyển khoản','VNPay','MoMo')),
    status          text not null default 'Thành công'
                    check (status in ('Chờ xác nhận','Thành công','Thất bại')),
    transaction_ref text,
    paid_by         uuid references public.profiles(id),
    paid_at         timestamptz not null default now(),
    note            text
);

create index if not exists ix_payments_invoice_id on public.payments(invoice_id);

-- Khi có thanh toán "Thành công" đủ hoặc vượt tổng tiền, tự chuyển hóa đơn
-- sang "Đã thanh toán". Đây là nguồn xác thực duy nhất — không có API nào
-- cho phép client tự đặt invoices.status = 'Đã thanh toán' trực tiếp.
create or replace function public.sync_invoice_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    target_invoice_id bigint;
    inv_total  numeric(14,0);
    paid_total numeric(14,0);
begin
    target_invoice_id := coalesce(new.invoice_id, old.invoice_id);

    select total_amount into inv_total from public.invoices where invoice_id = target_invoice_id;
    select coalesce(sum(amount), 0) into paid_total
      from public.payments
     where invoice_id = target_invoice_id and status = 'Thành công';

    if inv_total > 0 and paid_total >= inv_total then
        update public.invoices set status = 'Đã thanh toán', updated_at = now()
         where invoice_id = target_invoice_id and status <> 'Đã thanh toán';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_sync_invoice_status on public.payments;
create trigger trg_sync_invoice_status
    after insert or update on public.payments
    for each row execute function public.sync_invoice_status();

-- Hóa đơn đã "Đã thanh toán" thì KHÓA HẲN — không cho sửa/xóa nữa, kể cả
-- Admin. Cần điều chỉnh thì tạo hóa đơn/khoản mục mới, không sửa hóa đơn cũ,
-- để giữ đúng nguyên tắc kế toán (lịch sử không bị viết đè). Việc này cũng
-- tự động chặn luôn sửa/xóa invoice_items của hóa đơn đã thanh toán, vì
-- trigger trg_sync_invoice_total phía trên sẽ update invoices.updated_at và
-- rơi vào đúng trigger này, rollback toàn bộ giao dịch.
create or replace function public.protect_paid_invoice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if TG_OP = 'DELETE' then
        if old.status = 'Đã thanh toán' then
            raise exception 'Không thể xóa hóa đơn đã thanh toán.';
        end if;
        return old;
    end if;

    if old.status = 'Đã thanh toán' then
        raise exception 'Không thể chỉnh sửa hóa đơn đã thanh toán.';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_protect_paid_invoice on public.invoices;
create trigger trg_protect_paid_invoice
    before update or delete on public.invoices
    for each row execute function public.protect_paid_invoice();


/* =========================================================
   9d. THÔNG BÁO TỰ ĐỘNG (hóa đơn, lịch chăm sóc, cảnh báo sức khỏe)
   Trigger ghi vào public.notifications; trình duyệt nhận qua Supabase
   Realtime và hiện popup ở góc màn hình (wwwroot/js/notifications.js).
   Loại thông báo (notification_type): 'billing' | 'schedule' | 'health'.
   ========================================================= */

alter table public.care_schedules add column if not exists reminder_notified_at timestamptz;
alter table public.care_schedules add column if not exists late_notified_at timestamptz;
alter table public.invoices add column if not exists overdue_notified_at timestamptz;

create index if not exists ix_notifications_profile_created
    on public.notifications(profile_id, created_at desc);

-- Gửi 1 thông báo cho 1 tài khoản, tôn trọng notification_settings.
-- p_skip_actor: bỏ qua chính người vừa thao tác (tạo hóa đơn thì không tự báo cho mình).
create or replace function public.push_notification(
    p_profile_id uuid,
    p_resident_id bigint,
    p_type text,
    p_title text,
    p_message text,
    p_skip_actor boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    s public.notification_settings%rowtype;
begin
    if p_profile_id is null then return; end if;
    if p_skip_actor and p_profile_id = auth.uid() then return; end if;

    select * into s from public.notification_settings where profile_id = p_profile_id;
    if found then
        if p_type = 'schedule' and not s.enable_schedule_alerts then return; end if;
        if p_type = 'health' and not s.enable_health_alerts then return; end if;
        if p_type = 'billing' and not s.enable_system_alerts then return; end if;
    end if;

    insert into public.notifications (profile_id, resident_id, notification_type, title, message)
    values (p_profile_id, p_resident_id, p_type, p_title, p_message);
end;
$$;

-- Gửi cho: mọi tài khoản thuộc p_roles + (tùy chọn) người nhà có tài khoản của
-- cư dân + (tùy chọn) một tài khoản cụ thể (vd. nhân viên phụ trách). Không trùng lặp.
create or replace function public.notify_recipients(
    p_resident_id bigint,
    p_roles text[],
    p_include_family boolean,
    p_extra_profile uuid,
    p_type text,
    p_title text,
    p_message text,
    p_skip_actor boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    r record;
begin
    for r in
        select p.id as pid
          from public.profiles p
         where p.is_active and p.role = any(coalesce(p_roles, array[]::text[]))
        union
        select fm.profile_id
          from public.family_members fm
          join public.profiles p on p.id = fm.profile_id and p.is_active
         where p_include_family
           and fm.resident_id = p_resident_id
           and fm.is_active
        union
        select p.id
          from public.profiles p
         where p.id = p_extra_profile and p.is_active
    loop
        perform public.push_notification(r.pid, p_resident_id, p_type, p_title, p_message, p_skip_actor);
    end loop;
end;
$$;

-- Chỉ trigger/hàm nội bộ được gọi — client không tự bắn thông báo cho người khác
revoke execute on function public.push_notification(uuid, bigint, text, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.notify_recipients(bigint, text[], boolean, uuid, text, text, text, boolean) from public, anon, authenticated;

create or replace function public.format_vnd(n numeric)
returns text
language sql
immutable
as $$
    select replace(to_char(coalesce(n, 0), 'FM999,999,999,999,990'), ',', '.') || ' đ';
$$;

-- ---------- HÓA ĐƠN ----------
create or replace function public.notify_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    res_name text;
    label text;
    period text;
begin
    select full_name into res_name from public.residents where resident_id = new.resident_id;
    label := coalesce(new.invoice_code, '#' || new.invoice_id);
    period := new.billing_month || '/' || new.billing_year;

    if TG_OP = 'INSERT' then
        -- Lúc insert tổng tiền còn 0 (khoản mục thêm sau) nên không ghi số tiền
        perform public.notify_recipients(new.resident_id, array['admin','manager'], true, null, 'billing',
            'Hóa đơn mới ' || label,
            'Hóa đơn tháng ' || period || ' của ' || coalesce(res_name, 'cư dân') || ' đã được lập'
                || coalesce(', hạn thanh toán ' || to_char(new.due_date, 'DD/MM/YYYY'), '') || '.');
        return new;
    end if;

    if new.status is distinct from old.status then
        if new.status = 'Đã thanh toán' then
            perform public.notify_recipients(new.resident_id, array['admin','manager'], true, null, 'billing',
                'Đã thanh toán hóa đơn ' || label,
                'Hóa đơn tháng ' || period || ' của ' || coalesce(res_name, 'cư dân') || ' ('
                    || public.format_vnd(new.total_amount) || ') đã được thanh toán đầy đủ.');
        elsif new.status = 'Quá hạn' then
            perform public.notify_recipients(new.resident_id, array['admin','manager'], true, null, 'billing',
                'Hóa đơn ' || label || ' quá hạn',
                'Hóa đơn tháng ' || period || ' của ' || coalesce(res_name, 'cư dân') || ' ('
                    || public.format_vnd(new.total_amount) || ') đã quá hạn thanh toán.');
        elsif new.status = 'Đã hủy' then
            perform public.notify_recipients(new.resident_id, array['admin','manager'], true, null, 'billing',
                'Đã hủy hóa đơn ' || label,
                'Hóa đơn tháng ' || period || ' của ' || coalesce(res_name, 'cư dân') || ' đã bị hủy.');
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_notify_invoice_change on public.invoices;
create trigger trg_notify_invoice_change
    after insert or update of status on public.invoices
    for each row execute function public.notify_invoice_change();

-- ---------- THANH TOÁN ----------
-- "Chờ xác nhận" (người nhà tự báo chuyển khoản / tiền mặt) -> báo quản lý.
-- VNPay bỏ qua bước này vì IPN tự xác nhận. "Thất bại" -> báo người nhà.
create or replace function public.notify_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    inv public.invoices%rowtype;
    res_name text;
    label text;
begin
    select * into inv from public.invoices where invoice_id = new.invoice_id;
    select full_name into res_name from public.residents where resident_id = inv.resident_id;
    label := coalesce(inv.invoice_code, '#' || inv.invoice_id);

    if TG_OP = 'INSERT' and new.status = 'Chờ xác nhận' and new.method <> 'VNPay' then
        perform public.notify_recipients(inv.resident_id, array['admin','manager'], false, null, 'billing',
            'Thanh toán chờ xác nhận',
            'Có khoản ' || new.method || ' ' || public.format_vnd(new.amount) || ' cho hóa đơn ' || label
                || ' (' || coalesce(res_name, 'cư dân') || ') đang chờ xác nhận.');
    elsif new.status = 'Thất bại' and (TG_OP = 'INSERT' or old.status is distinct from new.status) then
        perform public.notify_recipients(inv.resident_id, array[]::text[], true, new.paid_by, 'billing',
            'Thanh toán không thành công',
            'Khoản thanh toán ' || public.format_vnd(new.amount) || ' cho hóa đơn ' || label
                || ' không thành công. Vui lòng thử lại.');
    end if;
    return new;
end;
$$;

drop trigger if exists trg_notify_payment_change on public.payments;
create trigger trg_notify_payment_change
    after insert or update of status on public.payments
    for each row execute function public.notify_payment_change();

-- ---------- LỊCH CHĂM SÓC ----------
-- Đổi ngày/giờ thì cho phép nhắc lại "sắp đến giờ" / "trễ"
create or replace function public.reset_care_schedule_notify_flags()
returns trigger
language plpgsql
as $$
begin
    if new.schedule_date is distinct from old.schedule_date or new.start_time is distinct from old.start_time then
        new.reminder_notified_at := null;
        new.late_notified_at := null;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_reset_care_schedule_notify_flags on public.care_schedules;
create trigger trg_reset_care_schedule_notify_flags
    before update on public.care_schedules
    for each row execute function public.reset_care_schedule_notify_flags();

create or replace function public.notify_care_schedule_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    res_name text;
    when_text text;
begin
    select full_name into res_name from public.residents where resident_id = new.resident_id;
    when_text := to_char(new.start_time, 'HH24:MI') || ' ngày ' || to_char(new.schedule_date, 'DD/MM/YYYY');

    if TG_OP = 'INSERT' then
        perform public.notify_recipients(new.resident_id, array[]::text[], true, new.assigned_staff_id, 'schedule',
            'Lịch chăm sóc mới',
            '"' || new.schedule_name || '" cho ' || coalesce(res_name, 'cư dân') || ' sẽ được thực hiện lúc ' || when_text || '.');
        return new;
    end if;

    if new.status = 'Hoàn thành' and old.status is distinct from 'Hoàn thành' then
        perform public.notify_recipients(new.resident_id, array[]::text[], true, new.assigned_staff_id, 'schedule',
            'Đã thực hiện lịch chăm sóc',
            '"' || new.schedule_name || '" cho ' || coalesce(res_name, 'cư dân') || ' (' || when_text || ') đã hoàn thành.');
    elsif new.assigned_staff_id is distinct from old.assigned_staff_id and new.assigned_staff_id is not null then
        perform public.push_notification(new.assigned_staff_id, new.resident_id, 'schedule',
            'Bạn được phân công lịch chăm sóc',
            '"' || new.schedule_name || '" cho ' || coalesce(res_name, 'cư dân') || ' lúc ' || when_text || '.');
    end if;
    return new;
end;
$$;

drop trigger if exists trg_notify_care_schedule_change on public.care_schedules;
create trigger trg_notify_care_schedule_change
    after insert or update of status, assigned_staff_id on public.care_schedules
    for each row execute function public.notify_care_schedule_change();

-- ---------- CẢNH BÁO SỨC KHỎE ----------
create or replace function public.notify_health_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    res_name text;
begin
    select full_name into res_name from public.residents where resident_id = new.resident_id;
    perform public.notify_recipients(new.resident_id, array['admin','manager','staff'], true, null, 'health',
        'Cảnh báo sức khỏe (' || new.severity || ')',
        coalesce(res_name, 'Cư dân') || ': ' || new.title || coalesce(' — ' || new.trigger_value, ''),
        false);
    return new;
end;
$$;

drop trigger if exists trg_notify_health_alert on public.health_alerts;
create trigger trg_notify_health_alert
    after insert on public.health_alerts
    for each row execute function public.notify_health_alert();

-- ---------- THÔNG BÁO THEO THỜI GIAN ----------
-- Lịch sắp đến giờ (30 phút tới), lịch trễ quá 1 tiếng chưa hoàn thành, hóa đơn
-- quá hạn. Mỗi mục chỉ báo 1 lần nhờ các cột *_notified_at. Chạy bằng pg_cron
-- mỗi 5 phút; trình duyệt cũng gọi định kỳ qua rpc để dự phòng khi chưa bật pg_cron.
create or replace function public.process_scheduled_notifications()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    r record;
    n integer := 0;
    tz constant text := 'Asia/Ho_Chi_Minh';
    local_today date := (now() at time zone tz)::date;
begin
    -- 1. Sắp đến giờ thực hiện
    for r in
        update public.care_schedules cs
           set reminder_notified_at = now()
          from public.residents re
         where re.resident_id = cs.resident_id
           and cs.reminder_notified_at is null
           and cs.status not in ('Hoàn thành', 'Đã hủy')
           and ((cs.schedule_date + cs.start_time) at time zone tz) between now() and now() + interval '30 minutes'
        returning cs.*, re.full_name as res_name
    loop
        perform public.notify_recipients(r.resident_id, array[]::text[], true, r.assigned_staff_id, 'schedule',
            'Sắp đến giờ chăm sóc',
            '"' || r.schedule_name || '" cho ' || r.res_name || ' sẽ được thực hiện lúc ' || to_char(r.start_time, 'HH24:MI') || ' hôm nay.',
            false);
        n := n + 1;
    end loop;

    -- 2. Trễ quá 1 tiếng mà chưa hoàn thành (chỉ xét lịch trong 24 giờ gần nhất,
    --    tránh bắn hàng loạt thông báo cho lịch cũ khi mới bật tính năng)
    for r in
        update public.care_schedules cs
           set late_notified_at = now()
          from public.residents re
         where re.resident_id = cs.resident_id
           and cs.late_notified_at is null
           and cs.status not in ('Hoàn thành', 'Đã hủy')
           and ((cs.schedule_date + cs.start_time) at time zone tz) between now() - interval '24 hours' and now() - interval '1 hour'
        returning cs.*, re.full_name as res_name
    loop
        perform public.notify_recipients(r.resident_id, array['admin','manager'], false, r.assigned_staff_id, 'schedule',
            'Lịch chăm sóc bị trễ',
            '"' || r.schedule_name || '" cho ' || r.res_name || ' (' || to_char(r.start_time, 'HH24:MI') || ' ngày '
                || to_char(r.schedule_date, 'DD/MM/YYYY') || ') đã trễ hơn 1 tiếng mà chưa hoàn thành.',
            false);
        n := n + 1;
    end loop;

    -- 3. Hóa đơn chưa thanh toán đã qua hạn (trong 30 ngày gần nhất)
    for r in
        update public.invoices i
           set overdue_notified_at = now()
          from public.residents re
         where re.resident_id = i.resident_id
           and i.overdue_notified_at is null
           and i.status = 'Chưa thanh toán'
           and i.due_date < local_today
           and i.due_date >= local_today - 30
        returning i.*, re.full_name as res_name
    loop
        perform public.notify_recipients(r.resident_id, array['admin','manager'], true, null, 'billing',
            'Hóa đơn ' || coalesce(r.invoice_code, '#' || r.invoice_id) || ' quá hạn',
            'Hóa đơn tháng ' || r.billing_month || '/' || r.billing_year || ' của ' || r.res_name || ' ('
                || public.format_vnd(r.total_amount) || ') đã quá hạn thanh toán ngày ' || to_char(r.due_date, 'DD/MM/YYYY') || '.',
            false);
        n := n + 1;
    end loop;

    return n;
end;
$$;

revoke execute on function public.process_scheduled_notifications() from public, anon;
grant execute on function public.process_scheduled_notifications() to authenticated;

-- Chạy định kỳ mỗi 5 phút nếu project bật được pg_cron (Database → Extensions).
-- Không có pg_cron thì vẫn chạy nhờ trình duyệt gọi rpc, chỉ là cần có người đang mở web.
do $$
begin
    begin
        create extension if not exists pg_cron;
    exception when others then
        raise notice 'Không bật được pg_cron: %', sqlerrm;
    end;

    if exists (select 1 from pg_extension where extname = 'pg_cron') then
        perform cron.schedule(
            'silvercare-scheduled-notifications',
            '*/5 * * * *',
            'select public.process_scheduled_notifications();'
        );
    end if;
end;
$$;

-- Bật Realtime cho bảng notifications để popup hiện ngay khi có thông báo mới
do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (
            select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
       ) then
        alter publication supabase_realtime add table public.notifications;
    end if;
end;
$$;


/* =========================================================
   10. ROW LEVEL SECURITY
   ========================================================= */

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.residents enable row level security;
alter table public.family_members enable row level security;
alter table public.health_records enable row level security;
alter table public.health_alerts enable row level security;
alter table public.alert_resolutions enable row level security;
alter table public.medicines enable row level security;
alter table public.medication_schedules enable row level security;
alter table public.medication_administrations enable row level security;
alter table public.care_schedules enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_settings enable row level security;
alter table public.app_settings enable row level security;
alter table public.service_packages enable row level security;
alter table public.resident_service_packages enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.payments enable row level security;

-- PROFILES
-- Staff/Manager/Admin thấy được hồ sơ cơ bản của nhau (cần để hiển thị/giao
-- "nhân viên phụ trách", "người cấp thuốc", "người ghi nhận"...).
-- Family chỉ thấy đúng hồ sơ của chính mình.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
    using (
        id = auth.uid()
        or public.user_role() in ('admin', 'manager', 'staff')
    );

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update
    using (id = auth.uid() or public.user_role() = 'admin');

-- ROOMS
drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms for select
    using (auth.role() = 'authenticated');

drop policy if exists rooms_write on public.rooms;
create policy rooms_write on public.rooms for all
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

-- RESIDENTS
drop policy if exists residents_select on public.residents;
create policy residents_select on public.residents for select
    using (
        public.user_role() in ('admin','manager','staff')
        or exists (
            select 1 from public.family_members fm
            where fm.resident_id = residents.resident_id
              and fm.profile_id = auth.uid()
        )
    );

drop policy if exists residents_write on public.residents;
create policy residents_write on public.residents for insert
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists residents_update on public.residents;
create policy residents_update on public.residents for update
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists residents_delete on public.residents;
create policy residents_delete on public.residents for delete
    using (public.user_role() in ('admin','manager'));

-- FAMILY MEMBERS
drop policy if exists family_members_select on public.family_members;
create policy family_members_select on public.family_members for select
    using (
        public.user_role() in ('admin','manager','staff')
        or profile_id = auth.uid()
    );

drop policy if exists family_members_write on public.family_members;
create policy family_members_write on public.family_members for all
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

-- HEALTH RECORDS
drop policy if exists health_records_select on public.health_records;
create policy health_records_select on public.health_records for select
    using (
        public.user_role() in ('admin','manager','staff')
        or exists (
            select 1 from public.family_members fm
            where fm.resident_id = health_records.resident_id
              and fm.profile_id = auth.uid()
        )
    );

drop policy if exists health_records_insert on public.health_records;
create policy health_records_insert on public.health_records for insert
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists health_records_update on public.health_records;
create policy health_records_update on public.health_records for update
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists health_records_delete on public.health_records;
create policy health_records_delete on public.health_records for delete
    using (public.user_role() in ('admin','manager'));

-- HEALTH ALERTS
drop policy if exists health_alerts_select on public.health_alerts;
create policy health_alerts_select on public.health_alerts for select
    using (
        public.user_role() in ('admin','manager','staff')
        or exists (
            select 1 from public.family_members fm
            where fm.resident_id = health_alerts.resident_id
              and fm.profile_id = auth.uid()
        )
    );

drop policy if exists health_alerts_write on public.health_alerts;
create policy health_alerts_write on public.health_alerts for all
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

-- ALERT RESOLUTIONS
drop policy if exists alert_resolutions_select on public.alert_resolutions;
create policy alert_resolutions_select on public.alert_resolutions for select
    using (public.user_role() in ('admin','manager','staff'));

drop policy if exists alert_resolutions_write on public.alert_resolutions;
create policy alert_resolutions_write on public.alert_resolutions for insert
    with check (public.user_role() in ('admin','manager','staff'));

-- MEDICINES
drop policy if exists medicines_select on public.medicines;
create policy medicines_select on public.medicines for select
    using (auth.role() = 'authenticated');

drop policy if exists medicines_write on public.medicines;
create policy medicines_write on public.medicines for all
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

-- MEDICATION SCHEDULES
drop policy if exists medication_schedules_select on public.medication_schedules;
create policy medication_schedules_select on public.medication_schedules for select
    using (
        public.user_role() in ('admin','manager','staff')
        or exists (
            select 1 from public.family_members fm
            where fm.resident_id = medication_schedules.resident_id
              and fm.profile_id = auth.uid()
        )
    );

drop policy if exists medication_schedules_write on public.medication_schedules;
create policy medication_schedules_write on public.medication_schedules for all
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

-- MEDICATION ADMINISTRATIONS
drop policy if exists medication_administrations_select on public.medication_administrations;
create policy medication_administrations_select on public.medication_administrations for select
    using (
        public.user_role() in ('admin','manager','staff')
        or exists (
            select 1
              from public.medication_schedules ms
              join public.family_members fm on fm.resident_id = ms.resident_id
             where ms.medication_schedule_id = medication_administrations.medication_schedule_id
               and fm.profile_id = auth.uid()
        )
    );

drop policy if exists medication_administrations_write on public.medication_administrations;
create policy medication_administrations_write on public.medication_administrations for all
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

-- CARE SCHEDULES
drop policy if exists care_schedules_select on public.care_schedules;
create policy care_schedules_select on public.care_schedules for select
    using (
        public.user_role() in ('admin','manager','staff')
        or exists (
            select 1 from public.family_members fm
            where fm.resident_id = care_schedules.resident_id
              and fm.profile_id = auth.uid()
        )
    );

drop policy if exists care_schedules_write on public.care_schedules;
create policy care_schedules_write on public.care_schedules for all
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

-- NOTIFICATIONS
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select
    using (profile_id = auth.uid() or public.user_role() = 'admin');

drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications for insert
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update
    using (profile_id = auth.uid() or public.user_role() = 'admin')
    with check (profile_id = auth.uid() or public.user_role() = 'admin');

-- NOTIFICATION SETTINGS
drop policy if exists notification_settings_select on public.notification_settings;
create policy notification_settings_select on public.notification_settings for select
    using (profile_id = auth.uid() or public.user_role() = 'admin');

drop policy if exists notification_settings_write on public.notification_settings;
create policy notification_settings_write on public.notification_settings for all
    using (profile_id = auth.uid() or public.user_role() = 'admin')
    with check (profile_id = auth.uid() or public.user_role() = 'admin');

-- APP SETTINGS
drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select on public.app_settings for select
    using (auth.role() = 'authenticated');

drop policy if exists app_settings_write on public.app_settings;
create policy app_settings_write on public.app_settings for update
    using (public.user_role() = 'admin')
    with check (public.user_role() = 'admin');

-- SERVICE PACKAGES — Staff không tham gia nghiệp vụ viện phí (theo ma trận quyền)
drop policy if exists service_packages_select on public.service_packages;
create policy service_packages_select on public.service_packages for select
    using (auth.role() = 'authenticated');

drop policy if exists service_packages_write on public.service_packages;
create policy service_packages_write on public.service_packages for all
    using (public.user_role() in ('admin', 'manager'))
    with check (public.user_role() in ('admin', 'manager'));

-- RESIDENT SERVICE PACKAGES
drop policy if exists resident_service_packages_select on public.resident_service_packages;
create policy resident_service_packages_select on public.resident_service_packages for select
    using (
        public.user_role() in ('admin', 'manager')
        or exists (
            select 1 from public.family_members fm
            where fm.resident_id = resident_service_packages.resident_id
              and fm.profile_id = auth.uid()
        )
    );

drop policy if exists resident_service_packages_write on public.resident_service_packages;
create policy resident_service_packages_write on public.resident_service_packages for all
    using (public.user_role() in ('admin', 'manager'))
    with check (public.user_role() in ('admin', 'manager'));

-- INVOICES
drop policy if exists invoices_select on public.invoices;
create policy invoices_select on public.invoices for select
    using (
        public.user_role() in ('admin', 'manager')
        or exists (
            select 1 from public.family_members fm
            where fm.resident_id = invoices.resident_id
              and fm.profile_id = auth.uid()
        )
    );

drop policy if exists invoices_write on public.invoices;
create policy invoices_write on public.invoices for all
    using (public.user_role() in ('admin', 'manager'))
    with check (public.user_role() in ('admin', 'manager'));

-- INVOICE ITEMS — quyền đọc đi theo hóa đơn cha, ghi chỉ Admin/Manager
drop policy if exists invoice_items_select on public.invoice_items;
create policy invoice_items_select on public.invoice_items for select
    using (
        exists (
            select 1 from public.invoices i
            where i.invoice_id = invoice_items.invoice_id
              and (
                  public.user_role() in ('admin', 'manager')
                  or exists (
                      select 1 from public.family_members fm
                      where fm.resident_id = i.resident_id
                        and fm.profile_id = auth.uid()
                  )
              )
        )
    );

drop policy if exists invoice_items_write on public.invoice_items;
create policy invoice_items_write on public.invoice_items for all
    using (public.user_role() in ('admin', 'manager'))
    with check (public.user_role() in ('admin', 'manager'));

-- PAYMENTS — Admin/Manager toàn quyền; Family chỉ được TỰ báo "đã chuyển khoản"
-- (status bắt buộc = 'Chờ xác nhận'), không thể tự đặt trạng thái thành công.
drop policy if exists payments_select on public.payments;
create policy payments_select on public.payments for select
    using (
        public.user_role() in ('admin', 'manager')
        or exists (
            select 1
              from public.invoices i
              join public.family_members fm on fm.resident_id = i.resident_id
             where i.invoice_id = payments.invoice_id
               and fm.profile_id = auth.uid()
        )
    );

drop policy if exists payments_insert on public.payments;
create policy payments_insert on public.payments for insert
    with check (
        public.user_role() in ('admin', 'manager')
        or (
            status = 'Chờ xác nhận'
            and exists (
                select 1
                  from public.invoices i
                  join public.family_members fm on fm.resident_id = i.resident_id
                 where i.invoice_id = payments.invoice_id
                   and fm.profile_id = auth.uid()
            )
        )
    );

drop policy if exists payments_update on public.payments;
create policy payments_update on public.payments for update
    using (public.user_role() in ('admin', 'manager'))
    with check (public.user_role() in ('admin', 'manager'));


/* =========================================================
   11. VIEWS CHO DASHBOARD
   ========================================================= */

create or replace view public.vw_dashboard_resident_statistics as
select
    count(*) as total_residents,
    sum(case when status = 'Đang ổn định' then 1 else 0 end) as stable_residents,
    sum(case when status = 'Cần theo dõi' then 1 else 0 end) as monitoring_residents,
    sum(case when status = 'Trung bình' then 1 else 0 end) as medium_residents
from public.residents
where is_active = true;

create or replace view public.vw_dashboard_alerts as
select
    count(*) as total_alerts,
    sum(case when status = 'Chưa xử lý' then 1 else 0 end) as unresolved_alerts,
    sum(case when severity = 'Cao' then 1 else 0 end) as high_severity_alerts
from public.health_alerts;

create or replace view public.vw_dashboard_medication as
select
    count(*) as total_medication_schedules,
    sum(case when status = 'Đang sử dụng' then 1 else 0 end) as active_medication_schedules
from public.medication_schedules;


/* =========================================================
   12. DỮ LIỆU MẪU (chạy với quyền chủ sở hữu, không bị RLS chặn)
   ========================================================= */

insert into public.rooms (room_code, room_name, floor_number, capacity, description)
select '201', 'Phòng 201', 2, 2, 'Phòng chăm sóc người cao tuổi'
where not exists (select 1 from public.rooms where room_code = '201');

insert into public.rooms (room_code, room_name, floor_number, capacity, description)
select '102', 'Phòng 102', 1, 2, 'Phòng chăm sóc người cao tuổi'
where not exists (select 1 from public.rooms where room_code = '102');

insert into public.rooms (room_code, room_name, floor_number, capacity, description)
select '305', 'Phòng 305', 3, 2, 'Phòng chăm sóc người cao tuổi'
where not exists (select 1 from public.rooms where room_code = '305');

insert into public.residents (resident_code, full_name, age, gender, room_id, blood_type, status, admission_date, medical_history, notes)
select 'NCT001', 'Nguyễn Văn An', 78, 'Nam', r.room_id, 'A+', 'Đang ổn định', '2024-05-15', 'Tiền sử huyết áp cao', 'Cần theo dõi huyết áp định kỳ'
from public.rooms r
where r.room_code = '201'
  and not exists (select 1 from public.residents where resident_code = 'NCT001');

insert into public.residents (resident_code, full_name, age, gender, room_id, blood_type, status, admission_date)
select 'NCT002', 'Lê Văn Bình', 82, 'Nam', r.room_id, 'B+', 'Cần theo dõi', '2024-06-10'
from public.rooms r
where r.room_code = '102'
  and not exists (select 1 from public.residents where resident_code = 'NCT002');

insert into public.residents (resident_code, full_name, age, gender, room_id, blood_type, status, admission_date)
select 'NCT003', 'Phạm Thị Cúc', 75, 'Nữ', r.room_id, 'O+', 'Đang ổn định', '2024-07-01'
from public.rooms r
where r.room_code = '305'
  and not exists (select 1 from public.residents where resident_code = 'NCT003');

insert into public.family_members (resident_id, full_name, relationship, phone, address, is_primary_contact)
select res.resident_id, 'Nguyễn Văn Hải', 'Con trai', '0909090909', '123 Nguyễn Trãi, Quận 1, TP. HCM', true
from public.residents res
where res.resident_code = 'NCT001'
  and not exists (select 1 from public.family_members where resident_id = res.resident_id);

insert into public.family_members (resident_id, full_name, relationship, phone, address, is_primary_contact)
select res.resident_id, 'Lê Thị Mai', 'Con gái', '0918888888', '456 Lê Lợi, Quận Gò Vấp, TP. HCM', true
from public.residents res
where res.resident_code = 'NCT002'
  and not exists (select 1 from public.family_members where resident_id = res.resident_id);

insert into public.family_members (resident_id, full_name, relationship, phone, address, is_primary_contact)
select res.resident_id, 'Trần Minh Hoàng', 'Chồng', '0989999999', '789 Cách Mạng Tháng 8, Quận 3, TP. HCM', true
from public.residents res
where res.resident_code = 'NCT003'
  and not exists (select 1 from public.family_members where resident_id = res.resident_id);

insert into public.medicines (medicine_name, generic_name, description)
select 'Paracetamol', 'Paracetamol', 'Thuốc giảm đau, hạ sốt'
where not exists (select 1 from public.medicines where medicine_name = 'Paracetamol');

insert into public.medicines (medicine_name, generic_name, description)
select 'Amlodipine', 'Amlodipine', 'Thuốc điều trị tăng huyết áp'
where not exists (select 1 from public.medicines where medicine_name = 'Amlodipine');

insert into public.service_packages (name, description, monthly_price)
select 'Gói Cơ bản', 'Ăn ở, sinh hoạt hằng ngày, theo dõi sức khỏe định kỳ', 8000000
where not exists (select 1 from public.service_packages where name = 'Gói Cơ bản');

insert into public.service_packages (name, description, monthly_price)
select 'Gói Nâng cao', 'Gói Cơ bản + chăm sóc y tế chuyên sâu, vật lý trị liệu', 14000000
where not exists (select 1 from public.service_packages where name = 'Gói Nâng cao');

insert into public.service_packages (name, description, monthly_price)
select 'Gói VIP', 'Phòng riêng, điều dưỡng 1-1, thực đơn dinh dưỡng riêng', 22000000
where not exists (select 1 from public.service_packages where name = 'Gói VIP');


/* =========================================================
   SAU KHI CHẠY FILE NÀY:
   1. Vào Authentication → Add user, tạo tài khoản Admin đầu tiên
      (đặt user_metadata: {"full_name": "...", "role": "admin"} khi tạo,
      hoặc tạo xong rồi chạy:
      update public.profiles set role = 'admin' where id = '<uuid vừa tạo>';)
   2. Deploy Edge Function supabase/functions/create-user để Admin có thể
      tạo thêm tài khoản nhân viên/quản lý từ trong app.
   ========================================================= */
