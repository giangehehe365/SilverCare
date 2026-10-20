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
    -- Vai trò tài khoản (role) là cố định không đổi sau khi tạo
    if auth.uid() is not null then
        new.role := old.role;
        if public.user_role() is distinct from 'admin' then
            new.is_active := old.is_active;
        end if;
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

-- created_at: thời điểm NHẬP (khác recorded_at là thời điểm ĐO) — để biết bản
-- ghi nào được nhập bù. severity: mức độ do DB tính (nguồn sự thật duy nhất,
-- UI chỉ hiển thị lại, không tự tính lệch pha nữa).
alter table public.health_records add column if not exists created_at timestamptz not null default now();
alter table public.health_records add column if not exists severity text;
alter table public.health_records add column if not exists is_backfilled boolean not null default false;

-- Giới hạn sinh lý hợp lệ (trước đây chỉ có min/max trên form HTML). NOT VALID
-- để không làm hỏng dữ liệu cũ — chỉ áp dụng cho bản ghi thêm/sửa từ giờ.
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'chk_health_records_vitals_range') then
        alter table public.health_records add constraint chk_health_records_vitals_range check (
            (systolic is null or systolic between 40 and 260)
            and (diastolic is null or diastolic between 30 and 180)
            and (systolic is null or diastolic is null or systolic > diastolic)
            and (heart_rate is null or heart_rate between 30 and 220)
            and (temperature is null or temperature between 30 and 45)
            and (oxygen_saturation is null or oxygen_saturation between 50 and 100)
            and (weight is null or weight between 20 and 200)
            and (blood_sugar is null or blood_sugar between 30 and 600)
        ) not valid;
    end if;
end;
$$;

-- Ngưỡng cảnh báo riêng cho từng cư dân (vd. cao huyết áp mãn tính thì nâng
-- ngưỡng tâm thu lên 160 để không báo động liên tục). Cột NULL = dùng ngưỡng mặc định.
create table if not exists public.resident_vital_thresholds (
    resident_id       bigint primary key references public.residents(resident_id) on delete cascade,
    systolic_high     int,
    systolic_low      int,
    diastolic_high    int,
    heart_rate_low    int,
    heart_rate_high   int,
    temperature_high  numeric(4,1),
    spo2_low          numeric(5,2),
    blood_sugar_low   numeric(6,2),
    blood_sugar_high  numeric(6,2),
    note              text,
    updated_by        uuid references public.profiles(id),
    updated_at        timestamptz not null default now()
);

-- Đánh giá sinh hiệu — dùng chung cho trigger cảnh báo và cột severity.
-- Mỗi chỉ số được xét ĐỘC LẬP: thiếu nhiệt độ vẫn phát hiện được SpO2 thấp.
-- Ngưỡng mặc định ("Cao" / "Trung bình"):
--   Huyết áp:  tâm thu >= 140 hoặc tâm trương >= 90, tâm thu < 90, hiệu áp <= 20 / tâm thu >= 120 hoặc tâm trương >= 80
--   Nhịp tim:  > 100 hoặc < 50 / 91-100 hoặc 50-59
--   Nhiệt độ:  >= 38.5 hoặc < 35 / 37.5-38.4
--   SpO2:      < 92 / 92-94
--   Đường huyết (mg/dL): < 70 hoặc >= 250 / 70-79 hoặc 180-249
create or replace function public.vital_assessment(
    p_resident_id bigint,
    p_sys int,
    p_dia int,
    p_hr int,
    p_temp numeric,
    p_spo2 numeric,
    p_sugar numeric,
    out severity text,
    out reasons text,
    out recommendation text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    t        public.resident_vital_thresholds%rowtype;
    sys_hi   int;
    sys_lo   int;
    dia_hi   int;
    hr_lo    int;
    hr_hi    int;
    temp_hi  numeric;
    spo2_lo  numeric;
    sugar_lo numeric;
    sugar_hi numeric;
    is_high  boolean := false;
    is_med   boolean := false;
    r        text[] := array[]::text[];
    rec      text := '';
begin
    select * into t from public.resident_vital_thresholds where resident_id = p_resident_id;
    sys_hi   := coalesce(t.systolic_high, 140);
    sys_lo   := coalesce(t.systolic_low, 90);
    dia_hi   := coalesce(t.diastolic_high, 90);
    hr_lo    := coalesce(t.heart_rate_low, 50);
    hr_hi    := coalesce(t.heart_rate_high, 100);
    temp_hi  := coalesce(t.temperature_high, 38.5);
    spo2_lo  := coalesce(t.spo2_low, 92);
    sugar_lo := coalesce(t.blood_sugar_low, 70);
    sugar_hi := coalesce(t.blood_sugar_high, 250);

    if p_sys is not null and p_dia is not null then
        if p_sys >= sys_hi or p_dia >= dia_hi then
            is_high := true;
            r := r || ('Huyết áp cao ' || p_sys || '/' || p_dia || ' mmHg');
            if p_sys >= sys_hi + 20 or p_dia >= dia_hi + 10 then
                rec := rec || 'Huyết áp tăng cao độ 2. Kiểm tra lại sau 30 phút nghỉ ngơi, nhắc uống thuốc hạ áp theo đơn, báo bác sĩ nếu không giảm. ';
            else
                rec := rec || 'Huyết áp cao. Theo dõi thêm, nhắc người bệnh nghỉ ngơi và dùng thuốc đúng giờ. ';
            end if;
        elsif p_sys < sys_lo then
            is_high := true;
            r := r || ('Huyết áp thấp ' || p_sys || '/' || p_dia || ' mmHg');
            rec := rec || 'Huyết áp thấp. Cho người bệnh nằm nghỉ, kê chân cao, theo dõi dấu hiệu chóng mặt/ngất. ';
        elsif p_sys - p_dia <= 20 then
            is_high := true;
            r := r || ('Hiệu áp kẹt ' || p_sys || '/' || p_dia || ' mmHg');
            rec := rec || 'Hiệu áp kẹt (chênh lệch tâm thu - tâm trương quá nhỏ). Đo lại ngay và báo bác sĩ. ';
        elsif p_sys >= sys_hi - 20 or p_dia >= dia_hi - 10 then
            is_med := true;
            r := r || ('Huyết áp hơi cao ' || p_sys || '/' || p_dia || ' mmHg');
        end if;
    end if;

    if p_hr is not null then
        if p_hr > hr_hi then
            is_high := true;
            r := r || ('Nhịp tim nhanh ' || p_hr || ' bpm');
            rec := rec || 'Nhịp tim nhanh bất thường, cần theo dõi sát và báo bác sĩ nếu kéo dài. ';
        elsif p_hr < hr_lo then
            is_high := true;
            r := r || ('Nhịp tim chậm ' || p_hr || ' bpm');
            rec := rec || 'Nhịp tim chậm bất thường, cần theo dõi sát và báo bác sĩ nếu kéo dài. ';
        elsif p_hr > hr_hi - 10 or p_hr < hr_lo + 10 then
            is_med := true;
            r := r || ('Nhịp tim ' || p_hr || ' bpm');
        end if;
    end if;

    if p_temp is not null then
        if p_temp >= temp_hi then
            is_high := true;
            r := r || ('Sốt cao ' || p_temp || '°C');
            rec := rec || 'Sốt cao, cần lau mát, bù nước điện giải và theo dõi nhiệt độ mỗi giờ. ';
        elsif p_temp < 35.0 then
            is_high := true;
            r := r || ('Thân nhiệt thấp ' || p_temp || '°C');
            rec := rec || 'Thân nhiệt thấp bất thường, cần giữ ấm và theo dõi sát. ';
        elsif p_temp >= temp_hi - 1 then
            is_med := true;
            r := r || ('Sốt nhẹ ' || p_temp || '°C');
        end if;
    end if;

    if p_spo2 is not null then
        if p_spo2 < spo2_lo then
            is_high := true;
            r := r || ('SpO2 thấp ' || p_spo2 || '%');
            rec := rec || 'SpO2 thấp, cần kiểm tra hô hấp, cho thở oxy nếu có chỉ định và báo bác sĩ ngay. ';
        elsif p_spo2 < spo2_lo + 3 then
            is_med := true;
            r := r || ('SpO2 ' || p_spo2 || '%');
        end if;
    end if;

    if p_sugar is not null then
        if p_sugar < sugar_lo then
            is_high := true;
            r := r || ('Hạ đường huyết ' || p_sugar || ' mg/dL');
            rec := rec || 'Hạ đường huyết: cho uống nước đường/ăn nhẹ ngay, đo lại sau 15 phút và báo bác sĩ. ';
        elsif p_sugar >= sugar_hi then
            is_high := true;
            r := r || ('Đường huyết cao ' || p_sugar || ' mg/dL');
            rec := rec || 'Đường huyết cao, kiểm tra chế độ ăn và thuốc tiểu đường, báo bác sĩ. ';
        elsif p_sugar >= sugar_hi - 70 or p_sugar < sugar_lo + 10 then
            is_med := true;
            r := r || ('Đường huyết ' || p_sugar || ' mg/dL');
        end if;
    end if;

    if is_high then
        severity := 'Cao';
    elsif is_med then
        severity := 'Trung bình';
    elsif coalesce(p_sys, p_dia, p_hr) is not null or coalesce(p_temp, p_spo2, p_sugar) is not null then
        severity := 'Bình thường';
    else
        severity := null;
    end if;

    reasons := array_to_string(r, '; ');
    recommendation := case
        when rec <> '' then trim(rec)
        when is_med then 'Chỉ số nằm trong vùng cần theo dõi thêm, chưa ở mức nguy hiểm.'
        else null
    end;
end;
$$;

-- Chuẩn hóa bản ghi trước khi lưu: người ghi luôn là tài khoản đang đăng nhập,
-- không cho ghi thời điểm tương lai, Staff chỉ được nhập bù tối đa 48 giờ,
-- tự đánh dấu "nhập bù" và tự tính severity.
create or replace function public.prepare_health_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    role_name text := public.user_role();
    a record;
begin
    if TG_OP = 'INSERT' then
        new.created_at := now();
        if auth.uid() is not null then
            new.recorded_by := auth.uid();
        end if;
    else
        new.created_at := old.created_at;
        if auth.uid() is not null and role_name = 'staff' then
            new.resident_id := old.resident_id;
            new.recorded_by := old.recorded_by;
        end if;
    end if;

    if new.recorded_at > now() + interval '5 minutes' then
        raise exception 'Không thể ghi chỉ số cho thời điểm trong tương lai.';
    end if;

    if auth.uid() is not null and role_name = 'staff' and new.recorded_at < now() - interval '48 hours' then
        raise exception 'Nhân viên chỉ được nhập bù chỉ số trong vòng 48 giờ. Liên hệ quản lý để nhập dữ liệu cũ hơn.';
    end if;

    new.is_backfilled := new.recorded_at < new.created_at - interval '1 hour';

    select * into a from public.vital_assessment(
        new.resident_id, new.systolic, new.diastolic, new.heart_rate,
        new.temperature, new.oxygen_saturation, new.blood_sugar
    );
    new.severity := a.severity;
    return new;
end;
$$;

drop trigger if exists trg_prepare_health_record on public.health_records;
create trigger trg_prepare_health_record
    before insert or update on public.health_records
    for each row execute function public.prepare_health_record();


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

create index if not exists ix_alert_resolutions_alert_id on public.alert_resolutions(alert_id);

-- Quy trình cảnh báo: 'Chưa xử lý' -> 'Đã tiếp nhận' (có người đang xử lý) -> 'Đã xử lý'.
-- escalated_at: thời điểm đã báo lên quản lý vì cảnh báo Cao quá lâu chưa ai tiếp nhận.
alter table public.health_alerts add column if not exists acknowledged_by uuid references public.profiles(id);
alter table public.health_alerts add column if not exists acknowledged_at timestamptz;
alter table public.health_alerts add column if not exists escalated_at timestamptz;

-- Tự động tạo health_alerts khi một health_records mới vượt ngưỡng an toàn, và
-- cập nhật trạng thái tổng quan của cư dân theo bản đo MỚI NHẤT (trước đây do
-- trình duyệt tự update residents.status, dễ lệch hoặc bị bỏ sót).
create or replace function public.evaluate_health_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    a       record;
    summary text;
begin
    select * into a from public.vital_assessment(
        new.resident_id, new.systolic, new.diastolic, new.heart_rate,
        new.temperature, new.oxygen_saturation, new.blood_sugar
    );

    if a.severity is null then
        return new;
    end if;

    if not exists (
        select 1 from public.health_records hr
         where hr.resident_id = new.resident_id
           and hr.health_record_id <> new.health_record_id
           and hr.recorded_at > new.recorded_at
    ) then
        update public.residents
           set status = case a.severity
                            when 'Cao' then 'Cần theo dõi'
                            when 'Trung bình' then 'Trung bình'
                            else 'Đang ổn định'
                        end,
               updated_at = now()
         where resident_id = new.resident_id;
    end if;

    if a.severity in ('Cao', 'Trung bình') then
        summary := concat_ws(', ',
            case when new.systolic is not null and new.diastolic is not null then new.systolic || '/' || new.diastolic || ' mmHg' end,
            case when new.heart_rate is not null then new.heart_rate || ' bpm' end,
            case when new.temperature is not null then new.temperature || '°C' end,
            case when new.oxygen_saturation is not null then 'SpO2 ' || new.oxygen_saturation || '%' end,
            case when new.blood_sugar is not null then 'ĐH ' || new.blood_sugar || ' mg/dL' end
        );

        insert into public.health_alerts
            (resident_id, health_record_id, alert_type, severity, title, message, trigger_value, ai_recommendation, status)
        values
        (
            new.resident_id,
            new.health_record_id,
            'Sinh hiệu bất thường',
            a.severity,
            'Chỉ số bất thường: ' || coalesce(nullif(a.reasons, ''), summary),
            'Hệ thống phát hiện chỉ số sinh hiệu vượt ngưỡng an toàn, cần nhân viên kiểm tra.'
                || case when new.is_backfilled then ' (Bản ghi nhập bù lúc ' || to_char(new.created_at at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ')' else '' end,
            summary,
            a.recommendation,
            'Chưa xử lý'
        );
    end if;

    return new;
end;
$$;

-- Bảo vệ quy trình xử lý cảnh báo:
--  * Staff chỉ được đổi trạng thái, không sửa nội dung cảnh báo.
--  * Muốn chuyển 'Đã xử lý' phải có ít nhất 1 bản ghi alert_resolutions trước.
--  * Cảnh báo đã xử lý chỉ Admin/Manager được mở lại.
create or replace function public.guard_health_alert_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    role_name text := public.user_role();
begin
    if auth.uid() is null then
        return new;
    end if;

    -- Bộ leo thang cảnh báo (process_scheduled_notifications) chỉ đánh dấu escalated_at
    if (to_jsonb(new) - 'escalated_at') = (to_jsonb(old) - 'escalated_at') then
        return new;
    end if;

    if role_name = 'staff' then
        new.resident_id := old.resident_id;
        new.health_record_id := old.health_record_id;
        new.alert_type := old.alert_type;
        new.severity := old.severity;
        new.title := old.title;
        new.message := old.message;
        new.trigger_value := old.trigger_value;
        new.ai_recommendation := old.ai_recommendation;
        new.created_at := old.created_at;
        new.escalated_at := old.escalated_at;
    end if;

    if new.status is distinct from old.status then
        if old.status = 'Đã xử lý' and role_name not in ('admin', 'manager') then
            raise exception 'Chỉ quản lý mới có thể mở lại cảnh báo đã xử lý.';
        end if;

        if new.status = 'Đã tiếp nhận' then
            new.acknowledged_by := auth.uid();
            new.acknowledged_at := now();
        elsif new.status = 'Đã xử lý' then
            if not exists (select 1 from public.alert_resolutions where alert_id = new.alert_id) then
                raise exception 'Cần ghi nhận biện pháp xử lý trước khi đóng cảnh báo.';
            end if;
            new.resolved_at := now();
            if new.acknowledged_at is null then
                new.acknowledged_by := auth.uid();
                new.acknowledged_at := now();
            end if;
        elsif new.status = 'Chưa xử lý' then
            new.acknowledged_by := null;
            new.acknowledged_at := null;
            new.resolved_at := null;
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_guard_health_alert_update on public.health_alerts;
create trigger trg_guard_health_alert_update
    before update on public.health_alerts
    for each row execute function public.guard_health_alert_update();

-- Ghi nhận xử lý: người xử lý luôn là tài khoản đăng nhập, bắt buộc mô tả
-- hành động, và cảnh báo mức Cao KHÔNG được đóng bằng "xử lý hàng loạt".
create or replace function public.guard_alert_resolution()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    sev text;
begin
    if auth.uid() is not null then
        new.resolved_by := auth.uid();
    end if;
    new.resolved_at := now();

    if length(trim(coalesce(new.action_taken, ''))) < 5 then
        raise exception 'Vui lòng mô tả cụ thể biện pháp đã thực hiện.';
    end if;

    select severity into sev from public.health_alerts where alert_id = new.alert_id;
    if sev = 'Cao' and new.resolution_type = 'Xử lý hàng loạt' then
        raise exception 'Cảnh báo mức Cao phải được xử lý và ghi nhận riêng từng trường hợp.';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_guard_alert_resolution on public.alert_resolutions;
create trigger trg_guard_alert_resolution
    before insert on public.alert_resolutions
    for each row execute function public.guard_alert_resolution();

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

-- Ghi nhận kết quả thực hiện: ai làm, lúc nào, kết quả/lý do không thực hiện được.
-- Lưu ý: bảng giờ có nhiều khóa ngoại tới profiles, khi nhúng phải chỉ rõ
-- profiles!care_schedules_assigned_staff_id_fkey(...) thay vì profiles(...).
alter table public.care_schedules add column if not exists created_by uuid references public.profiles(id);
alter table public.care_schedules add column if not exists started_at timestamptz;
alter table public.care_schedules add column if not exists completed_by uuid references public.profiles(id);
alter table public.care_schedules add column if not exists completed_at timestamptz;
alter table public.care_schedules add column if not exists result_note text;

create index if not exists ix_care_schedules_assigned_staff on public.care_schedules(assigned_staff_id, schedule_date);

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'chk_care_schedules_status') then
        alter table public.care_schedules add constraint chk_care_schedules_status
            check (status in ('Chưa thực hiện', 'Đang thực hiện', 'Hoàn thành', 'Không thực hiện được', 'Đã hủy'))
            not valid;
    end if;
end;
$$;

-- Quy tắc nghiệp vụ lịch chăm sóc (áp dụng khi chạy qua phiên đăng nhập app):
--  * Staff tạo lịch thì lịch luôn giao cho chính mình.
--  * Staff chỉ cập nhật lịch được giao cho mình; không được đổi người phụ trách;
--    chỉ sửa nội dung (tên, giờ, cư dân...) với lịch do chính mình tạo.
--  * Lịch đã chốt (Hoàn thành / Không thực hiện được) thì Staff không sửa được nữa.
--  * Hoàn thành / Không thực hiện được bắt buộc có ghi chú kết quả / lý do,
--    tự lưu người và thời điểm chốt.
create or replace function public.guard_care_schedule()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    role_name   text := public.user_role();
    local_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
    if TG_OP = 'INSERT' then
        if auth.uid() is not null then
            new.created_by := auth.uid();
            if role_name = 'staff' then
                new.assigned_staff_id := auth.uid();
                new.status := 'Chưa thực hiện';
            end if;
        end if;
        return new;
    end if;

    -- Bộ nhắc lịch (process_scheduled_notifications) chỉ đánh dấu cờ đã báo —
    -- hàm này có thể được trình duyệt của bất kỳ nhân viên nào gọi qua rpc.
    if (to_jsonb(new) - 'reminder_notified_at' - 'late_notified_at')
       = (to_jsonb(old) - 'reminder_notified_at' - 'late_notified_at') then
        return new;
    end if;

    if auth.uid() is not null and role_name = 'staff' then
        if old.assigned_staff_id is distinct from auth.uid() then
            raise exception 'Bạn chỉ được cập nhật lịch chăm sóc được phân công cho mình.';
        end if;
        if old.status in ('Hoàn thành', 'Không thực hiện được', 'Đã hủy') then
            raise exception 'Lịch này đã được chốt kết quả, chỉ quản lý mới có thể sửa.';
        end if;

        new.assigned_staff_id := old.assigned_staff_id;
        new.created_by := old.created_by;
        if old.created_by is distinct from auth.uid() then
            new.resident_id := old.resident_id;
            new.schedule_name := old.schedule_name;
            new.schedule_date := old.schedule_date;
            new.start_time := old.start_time;
            new.end_time := old.end_time;
            new.schedule_type := old.schedule_type;
            new.note := old.note;
        end if;

        if new.status in ('Đang thực hiện', 'Hoàn thành') and new.status is distinct from old.status
           and new.schedule_date > local_today then
            raise exception 'Chưa đến ngày thực hiện lịch này.';
        end if;
        if new.status = 'Đã hủy' and old.status is distinct from 'Đã hủy' then
            raise exception 'Chỉ quản lý mới có thể hủy lịch chăm sóc.';
        end if;
    end if;

    if new.status is distinct from old.status then
        if new.status = 'Đang thực hiện' then
            new.started_at := coalesce(new.started_at, now());
        elsif new.status in ('Hoàn thành', 'Không thực hiện được') then
            if auth.uid() is not null and length(trim(coalesce(new.result_note, ''))) = 0 then
                raise exception '%', case when new.status = 'Hoàn thành'
                    then 'Vui lòng ghi nhận kết quả thực hiện trước khi hoàn thành.'
                    else 'Vui lòng ghi rõ lý do không thực hiện được.' end;
            end if;
            new.completed_by := coalesce(auth.uid(), new.completed_by);
            new.completed_at := now();
        elsif new.status = 'Chưa thực hiện' then
            new.started_at := null;
            new.completed_by := null;
            new.completed_at := null;
        end if;
    end if;

    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists trg_guard_care_schedule on public.care_schedules;
create trigger trg_guard_care_schedule
    before insert or update on public.care_schedules
    for each row execute function public.guard_care_schedule();


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
            '"' || new.schedule_name || '" cho ' || coalesce(res_name, 'cư dân') || ' (' || when_text || ') đã hoàn thành.'
                || coalesce(' Kết quả: ' || nullif(trim(new.result_note), ''), ''));
    elsif new.status = 'Không thực hiện được' and old.status is distinct from 'Không thực hiện được' then
        -- Chỉ báo nội bộ (quản lý) để sắp xếp lại, không báo người nhà
        perform public.notify_recipients(new.resident_id, array['admin','manager'], false, new.assigned_staff_id, 'schedule',
            'Lịch chăm sóc không thực hiện được',
            '"' || new.schedule_name || '" cho ' || coalesce(res_name, 'cư dân') || ' (' || when_text || ') không thực hiện được.'
                || coalesce(' Lý do: ' || nullif(trim(new.result_note), ''), ''));
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
-- quá hạn, cảnh báo sức khỏe mức Cao quá 15 phút chưa ai tiếp nhận.
-- Mỗi mục chỉ báo 1 lần nhờ các cột *_notified_at / escalated_at. Chạy bằng pg_cron
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
           and cs.status not in ('Hoàn thành', 'Đã hủy', 'Không thực hiện được')
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
           and cs.status not in ('Hoàn thành', 'Đã hủy', 'Không thực hiện được')
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

    -- 4. Leo thang: cảnh báo sức khỏe mức Cao quá 15 phút chưa ai tiếp nhận
    --    (chỉ xét cảnh báo trong 24 giờ gần nhất)
    for r in
        update public.health_alerts a
           set escalated_at = now()
          from public.residents re
         where re.resident_id = a.resident_id
           and a.escalated_at is null
           and a.status = 'Chưa xử lý'
           and a.severity = 'Cao'
           and a.created_at between now() - interval '24 hours' and now() - interval '15 minutes'
        returning a.*, re.full_name as res_name
    loop
        perform public.notify_recipients(r.resident_id, array['admin','manager'], false, null, 'health',
            'Cảnh báo Cao chưa được tiếp nhận',
            r.res_name || ': "' || r.title || '" từ ' || to_char(r.created_at at time zone tz, 'HH24:MI DD/MM')
                || ' đã quá 15 phút mà chưa có nhân viên tiếp nhận.',
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
   9e. NGHIỆP VỤ CHĂM SÓC CỦA NHÂN VIÊN
   (đo lại sau cảnh báo, nhật ký chăm sóc & sự cố, bàn giao ca, nhật ký thao tác)
   ========================================================= */

-- ---------- ĐO LẠI SAU KHI XỬ LÝ CẢNH BÁO CAO ----------
-- Đóng một cảnh báo mức Cao thì tự tạo lịch "Đo lại sinh hiệu" sau 30 phút,
-- giao cho chính người xử lý — để xác nhận can thiệp thật sự có hiệu quả.
create or replace function public.schedule_recheck_after_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    due timestamp := (now() at time zone 'Asia/Ho_Chi_Minh') + interval '30 minutes';
begin
    if new.status = 'Đã xử lý' and old.status is distinct from 'Đã xử lý' and new.severity = 'Cao' then
        insert into public.care_schedules
            (resident_id, assigned_staff_id, schedule_name, schedule_date, start_time, schedule_type, status, note)
        values
            (new.resident_id, auth.uid(), 'Đo lại sinh hiệu sau cảnh báo', due::date, due::time, 'Y tế', 'Chưa thực hiện',
             'Tự động tạo sau khi xử lý cảnh báo: ' || new.title);
    end if;
    return new;
end;
$$;

drop trigger if exists trg_schedule_recheck_after_alert on public.health_alerts;
create trigger trg_schedule_recheck_after_alert
    after update of status on public.health_alerts
    for each row execute function public.schedule_recheck_after_alert();

-- ---------- NHẬT KÝ CHĂM SÓC & SỰ CỐ ----------
-- Ghi nhận các sự kiện ngoài lịch: ăn uống, vệ sinh, tinh thần, da/vết loét,
-- té ngã, sự cố khác. Té ngã hoặc mức Cao được coi là sự cố: báo quản lý và
-- người nhà ngay.
create table if not exists public.care_notes (
    care_note_id     bigint generated always as identity primary key,
    resident_id      bigint not null references public.residents(resident_id) on delete cascade,
    author_id        uuid references public.profiles(id),
    note_type        text not null default 'Ghi chú'
                     check (note_type in ('Ghi chú','Ăn uống','Vệ sinh','Tinh thần/Hành vi','Da/Vết loét','Té ngã','Sự cố khác')),
    severity         text not null default 'Thấp'
                     check (severity in ('Thấp','Trung bình','Cao')),
    content          text not null check (length(trim(content)) > 0),
    action_taken     text,
    occurred_at      timestamptz not null default now(),
    is_incident      boolean not null default false,
    family_notified  boolean not null default false,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz
);

create index if not exists ix_care_notes_resident_occurred on public.care_notes(resident_id, occurred_at desc);

create or replace function public.prepare_care_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if TG_OP = 'INSERT' then
        new.created_at := now();
        if auth.uid() is not null then
            new.author_id := auth.uid();
        end if;
    else
        new.author_id := old.author_id;
        new.resident_id := old.resident_id;
        new.created_at := old.created_at;
        new.updated_at := now();
    end if;

    if new.occurred_at > now() + interval '5 minutes' then
        raise exception 'Thời điểm xảy ra không thể ở tương lai.';
    end if;

    new.is_incident := new.note_type in ('Té ngã', 'Sự cố khác') or new.severity = 'Cao';
    new.family_notified := new.note_type = 'Té ngã' or new.severity = 'Cao';

    if new.is_incident and length(trim(coalesce(new.action_taken, ''))) = 0 then
        raise exception 'Sự cố cần ghi rõ biện pháp đã xử lý.';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_prepare_care_note on public.care_notes;
create trigger trg_prepare_care_note
    before insert or update on public.care_notes
    for each row execute function public.prepare_care_note();

create or replace function public.notify_care_incident()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    res_name text;
begin
    if not new.is_incident then
        return new;
    end if;
    select full_name into res_name from public.residents where resident_id = new.resident_id;
    perform public.notify_recipients(new.resident_id, array['admin','manager'], new.family_notified, null, 'health',
        'Sự cố: ' || new.note_type || ' (' || new.severity || ')',
        coalesce(res_name, 'Cư dân') || ' — ' || left(new.content, 200)
            || coalesce('. Đã xử lý: ' || left(nullif(trim(new.action_taken), ''), 200), ''));
    return new;
end;
$$;

drop trigger if exists trg_notify_care_incident on public.care_notes;
create trigger trg_notify_care_incident
    after insert on public.care_notes
    for each row execute function public.notify_care_incident();

-- ---------- BÀN GIAO CA ----------
create table if not exists public.shift_handovers (
    handover_id         bigint generated always as identity primary key,
    shift_date          date not null default ((now() at time zone 'Asia/Ho_Chi_Minh')::date),
    shift               text not null check (shift in ('Sáng','Chiều','Đêm')),
    from_staff_id       uuid references public.profiles(id),
    to_staff_id         uuid references public.profiles(id),
    summary             text not null check (length(trim(summary)) > 0),
    pending_tasks       text,
    residents_to_watch  text,
    acknowledged_at     timestamptz,
    acknowledge_note    text,
    created_at          timestamptz not null default now()
);

create index if not exists ix_shift_handovers_date on public.shift_handovers(shift_date desc, created_at desc);

-- Người giao luôn là tài khoản đăng nhập; người nhận chỉ được bấm "Đã nhận"
-- (kèm ghi chú), không sửa nội dung bàn giao; bàn giao đã nhận thì khóa.
create or replace function public.guard_shift_handover()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if TG_OP = 'INSERT' then
        if auth.uid() is not null then
            new.from_staff_id := auth.uid();
        end if;
        if new.to_staff_id = new.from_staff_id then
            raise exception 'Không thể bàn giao ca cho chính mình.';
        end if;
        new.acknowledged_at := null;
        new.created_at := now();
        return new;
    end if;

    if auth.uid() is null or public.user_role() in ('admin', 'manager') then
        return new;
    end if;

    if old.acknowledged_at is not null then
        raise exception 'Bàn giao ca đã được xác nhận, không thể sửa.';
    end if;

    if auth.uid() = old.to_staff_id and auth.uid() is distinct from old.from_staff_id then
        new.shift_date := old.shift_date;
        new.shift := old.shift;
        new.from_staff_id := old.from_staff_id;
        new.to_staff_id := old.to_staff_id;
        new.summary := old.summary;
        new.pending_tasks := old.pending_tasks;
        new.residents_to_watch := old.residents_to_watch;
        new.created_at := old.created_at;
        if new.acknowledged_at is not null then
            new.acknowledged_at := now();
        end if;
    else
        new.from_staff_id := old.from_staff_id;
        new.created_at := old.created_at;
        new.acknowledged_at := old.acknowledged_at;
        new.acknowledge_note := old.acknowledge_note;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_guard_shift_handover on public.shift_handovers;
create trigger trg_guard_shift_handover
    before insert or update on public.shift_handovers
    for each row execute function public.guard_shift_handover();

create or replace function public.notify_shift_handover()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    from_name text;
    to_name   text;
begin
    select full_name into from_name from public.profiles where id = new.from_staff_id;
    select full_name into to_name from public.profiles where id = new.to_staff_id;

    if TG_OP = 'INSERT' then
        perform public.push_notification(new.to_staff_id, null, 'schedule',
            'Bàn giao ca ' || new.shift || ' ' || to_char(new.shift_date, 'DD/MM'),
            coalesce(from_name, 'Đồng nghiệp') || ' đã bàn giao ca cho bạn. Vui lòng xem và xác nhận đã nhận.');
    elsif new.acknowledged_at is not null and old.acknowledged_at is null then
        perform public.push_notification(new.from_staff_id, null, 'schedule',
            'Đã nhận bàn giao ca ' || new.shift || ' ' || to_char(new.shift_date, 'DD/MM'),
            coalesce(to_name, 'Đồng nghiệp') || ' đã xác nhận nhận ca.'
                || coalesce(' Ghi chú: ' || nullif(trim(new.acknowledge_note), ''), ''));
    end if;
    return new;
end;
$$;

drop trigger if exists trg_notify_shift_handover on public.shift_handovers;
create trigger trg_notify_shift_handover
    after insert or update of acknowledged_at on public.shift_handovers
    for each row execute function public.notify_shift_handover();

-- ---------- NHẬT KÝ THAO TÁC (AUDIT) ----------
-- Ghi lại mọi lần SỬA / XÓA trên dữ liệu chăm sóc: ai, lúc nào, giá trị cũ -> mới.
-- Chỉ lưu các trường thực sự thay đổi; bỏ qua cờ kỹ thuật của bộ nhắc thông báo.
create table if not exists public.audit_log (
    audit_id    bigint generated always as identity primary key,
    table_name  text not null,
    record_id   text,
    action      text not null check (action in ('UPDATE','DELETE')),
    changed_by  uuid references public.profiles(id) on delete set null,
    changed_at  timestamptz not null default now(),
    old_data    jsonb,
    new_data    jsonb
);

create index if not exists ix_audit_log_changed_at on public.audit_log(changed_at desc);
create index if not exists ix_audit_log_record on public.audit_log(table_name, record_id);

create or replace function public.log_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    pk_col   text := TG_ARGV[0];
    ignored  text[] := array['updated_at','reminder_notified_at','late_notified_at','overdue_notified_at','escalated_at'];
    o        jsonb;
    n        jsonb;
    old_diff jsonb := '{}'::jsonb;
    new_diff jsonb := '{}'::jsonb;
    k        text;
begin
    o := to_jsonb(old);

    if TG_OP = 'DELETE' then
        insert into public.audit_log (table_name, record_id, action, changed_by, old_data)
        values (TG_TABLE_NAME, o ->> pk_col, 'DELETE', auth.uid(), o);
        return old;
    end if;

    n := to_jsonb(new);
    for k in select jsonb_object_keys(n) loop
        if k <> all(ignored) and (o -> k) is distinct from (n -> k) then
            old_diff := old_diff || jsonb_build_object(k, o -> k);
            new_diff := new_diff || jsonb_build_object(k, n -> k);
        end if;
    end loop;

    if new_diff <> '{}'::jsonb then
        insert into public.audit_log (table_name, record_id, action, changed_by, old_data, new_data)
        values (TG_TABLE_NAME, n ->> pk_col, 'UPDATE', auth.uid(), old_diff, new_diff);
    end if;
    return new;
end;
$$;

drop trigger if exists trg_audit_health_records on public.health_records;
create trigger trg_audit_health_records
    after update or delete on public.health_records
    for each row execute function public.log_audit('health_record_id');

drop trigger if exists trg_audit_care_schedules on public.care_schedules;
create trigger trg_audit_care_schedules
    after update or delete on public.care_schedules
    for each row execute function public.log_audit('care_schedule_id');

drop trigger if exists trg_audit_health_alerts on public.health_alerts;
create trigger trg_audit_health_alerts
    after update or delete on public.health_alerts
    for each row execute function public.log_audit('alert_id');

drop trigger if exists trg_audit_residents on public.residents;
create trigger trg_audit_residents
    after update or delete on public.residents
    for each row execute function public.log_audit('resident_id');

drop trigger if exists trg_audit_care_notes on public.care_notes;
create trigger trg_audit_care_notes
    after update or delete on public.care_notes
    for each row execute function public.log_audit('care_note_id');

drop trigger if exists trg_audit_resident_vital_thresholds on public.resident_vital_thresholds;
create trigger trg_audit_resident_vital_thresholds
    after update or delete on public.resident_vital_thresholds
    for each row execute function public.log_audit('resident_id');


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
alter table public.resident_vital_thresholds enable row level security;
alter table public.care_notes enable row level security;
alter table public.shift_handovers enable row level security;
alter table public.audit_log enable row level security;

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

-- Danh mục phòng là việc của quản lý; Staff chỉ đọc
drop policy if exists rooms_write on public.rooms;
create policy rooms_write on public.rooms for all
    using (public.user_role() in ('admin','manager'))
    with check (public.user_role() in ('admin','manager'));

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

-- Staff chỉ sửa được bản ghi DO CHÍNH MÌNH nhập, trong vòng 24 giờ sau khi nhập
-- (mọi lần sửa đều vào audit_log). Admin/Manager sửa được mọi bản ghi.
drop policy if exists health_records_update on public.health_records;
create policy health_records_update on public.health_records for update
    using (
        public.user_role() in ('admin','manager')
        or (
            public.user_role() = 'staff'
            and recorded_by = auth.uid()
            and created_at > now() - interval '24 hours'
        )
    )
    with check (
        public.user_role() in ('admin','manager')
        or (public.user_role() = 'staff' and recorded_by = auth.uid())
    );

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

-- Cảnh báo do trigger tạo; Staff chỉ được cập nhật trạng thái (tiếp nhận / xử lý,
-- xem guard_health_alert_update), không tạo tay và không xóa.
drop policy if exists health_alerts_write on public.health_alerts;

drop policy if exists health_alerts_insert on public.health_alerts;
create policy health_alerts_insert on public.health_alerts for insert
    with check (public.user_role() in ('admin','manager'));

drop policy if exists health_alerts_update on public.health_alerts;
create policy health_alerts_update on public.health_alerts for update
    using (public.user_role() in ('admin','manager','staff'))
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists health_alerts_delete on public.health_alerts;
create policy health_alerts_delete on public.health_alerts for delete
    using (public.user_role() in ('admin','manager'));

-- ALERT RESOLUTIONS — chỉ thêm mới (lịch sử xử lý không được sửa/xóa)
drop policy if exists alert_resolutions_select on public.alert_resolutions;
create policy alert_resolutions_select on public.alert_resolutions for select
    using (public.user_role() in ('admin','manager','staff'));

drop policy if exists alert_resolutions_write on public.alert_resolutions;
create policy alert_resolutions_write on public.alert_resolutions for insert
    with check (
        public.user_role() in ('admin','manager','staff')
        and resolved_by = auth.uid()
    );

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

-- Staff: tạo lịch cho chính mình, cập nhật lịch được giao cho mình, chỉ xóa
-- lịch do chính mình tạo và chưa bắt đầu. Phân công / hủy / xóa lịch khác là
-- việc của Admin/Manager. Chi tiết cột nào được sửa: xem guard_care_schedule.
drop policy if exists care_schedules_write on public.care_schedules;

drop policy if exists care_schedules_insert on public.care_schedules;
create policy care_schedules_insert on public.care_schedules for insert
    with check (
        public.user_role() in ('admin','manager')
        or (public.user_role() = 'staff' and assigned_staff_id = auth.uid())
    );

drop policy if exists care_schedules_update on public.care_schedules;
create policy care_schedules_update on public.care_schedules for update
    using (
        public.user_role() in ('admin','manager')
        or (public.user_role() = 'staff' and assigned_staff_id = auth.uid())
    )
    with check (
        public.user_role() in ('admin','manager')
        or (public.user_role() = 'staff' and assigned_staff_id = auth.uid())
    );

drop policy if exists care_schedules_delete on public.care_schedules;
create policy care_schedules_delete on public.care_schedules for delete
    using (
        public.user_role() in ('admin','manager')
        or (
            public.user_role() = 'staff'
            and created_by = auth.uid()
            and assigned_staff_id = auth.uid()
            and status = 'Chưa thực hiện'
        )
    );

-- NOTIFICATIONS
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select
    using (profile_id = auth.uid() or public.user_role() = 'admin');

-- Không có policy INSERT: thông báo chỉ được tạo bởi trigger/hàm security
-- definer (push_notification). Trước đây Staff có thể tự insert thông báo
-- giả cho bất kỳ tài khoản nào, kể cả người nhà.
drop policy if exists notifications_insert on public.notifications;

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

-- RESIDENT VITAL THRESHOLDS — nhân viên xem được để hiểu vì sao có cảnh báo,
-- chỉ Admin/Manager đặt ngưỡng
drop policy if exists resident_vital_thresholds_select on public.resident_vital_thresholds;
create policy resident_vital_thresholds_select on public.resident_vital_thresholds for select
    using (public.user_role() in ('admin','manager','staff'));

drop policy if exists resident_vital_thresholds_write on public.resident_vital_thresholds;
create policy resident_vital_thresholds_write on public.resident_vital_thresholds for all
    using (public.user_role() in ('admin','manager'))
    with check (public.user_role() in ('admin','manager'));

-- CARE NOTES — người nhà chỉ thấy các ghi nhận đã được báo cho gia đình
drop policy if exists care_notes_select on public.care_notes;
create policy care_notes_select on public.care_notes for select
    using (
        public.user_role() in ('admin','manager','staff')
        or (
            family_notified
            and exists (
                select 1 from public.family_members fm
                where fm.resident_id = care_notes.resident_id
                  and fm.profile_id = auth.uid()
            )
        )
    );

drop policy if exists care_notes_insert on public.care_notes;
create policy care_notes_insert on public.care_notes for insert
    with check (
        public.user_role() in ('admin','manager','staff')
        and author_id = auth.uid()
    );

drop policy if exists care_notes_update on public.care_notes;
create policy care_notes_update on public.care_notes for update
    using (
        public.user_role() in ('admin','manager')
        or (author_id = auth.uid() and created_at > now() - interval '24 hours')
    )
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists care_notes_delete on public.care_notes;
create policy care_notes_delete on public.care_notes for delete
    using (public.user_role() in ('admin','manager'));

-- SHIFT HANDOVERS
drop policy if exists shift_handovers_select on public.shift_handovers;
create policy shift_handovers_select on public.shift_handovers for select
    using (public.user_role() in ('admin','manager','staff'));

drop policy if exists shift_handovers_insert on public.shift_handovers;
create policy shift_handovers_insert on public.shift_handovers for insert
    with check (
        public.user_role() in ('admin','manager','staff')
        and from_staff_id = auth.uid()
    );

drop policy if exists shift_handovers_update on public.shift_handovers;
create policy shift_handovers_update on public.shift_handovers for update
    using (
        public.user_role() in ('admin','manager')
        or from_staff_id = auth.uid()
        or to_staff_id = auth.uid()
    )
    with check (public.user_role() in ('admin','manager','staff'));

drop policy if exists shift_handovers_delete on public.shift_handovers;
create policy shift_handovers_delete on public.shift_handovers for delete
    using (public.user_role() in ('admin','manager'));

-- AUDIT LOG — chỉ đọc, chỉ Admin/Manager; ghi bởi trigger log_audit
drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select on public.audit_log for select
    using (public.user_role() in ('admin','manager'));


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
    sum(case when status <> 'Đã xử lý' then 1 else 0 end) as unresolved_alerts,
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
