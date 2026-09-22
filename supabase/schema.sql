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
    id            int primary key default 1 check (id = 1),
    org_name      text not null default 'SilverCare',
    org_address   text,
    org_hotline   text,
    updated_at    timestamptz not null default now()
);

insert into public.app_settings (id) values (1)
on conflict (id) do nothing;


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


/* =========================================================
   SAU KHI CHẠY FILE NÀY:
   1. Vào Authentication → Add user, tạo tài khoản Admin đầu tiên
      (đặt user_metadata: {"full_name": "...", "role": "admin"} khi tạo,
      hoặc tạo xong rồi chạy:
      update public.profiles set role = 'admin' where id = '<uuid vừa tạo>';)
   2. Deploy Edge Function supabase/functions/create-user để Admin có thể
      tạo thêm tài khoản nhân viên/quản lý từ trong app.
   ========================================================= */
