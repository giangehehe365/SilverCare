/* =========================================================
   SILVERCARE DATABASE
   SQL SERVER
   ========================================================= */

USE master;
GO

/* =========================================================
   1. CREATE DATABASE
   ========================================================= */

IF DB_ID('SilverCare') IS NULL
BEGIN
    CREATE DATABASE SilverCare;
END
GO

USE SilverCare;
GO


/* =========================================================
   2. ROLES
   ========================================================= */

IF OBJECT_ID('dbo.Roles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Roles
    (
        RoleId          INT IDENTITY(1,1) PRIMARY KEY,
        RoleName        NVARCHAR(50) NOT NULL UNIQUE,
        Description     NVARCHAR(255) NULL,
        IsActive        BIT NOT NULL DEFAULT 1,
        CreatedAt       DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );
END
GO


/* =========================================================
   3. ROLES DATA
   ========================================================= */

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Admin')
    INSERT INTO dbo.Roles (RoleName, Description)
    VALUES ('Admin', N'Quản trị hệ thống');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Manager')
    INSERT INTO dbo.Roles (RoleName, Description)
    VALUES ('Manager', N'Quản lý trung tâm');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Staff')
    INSERT INTO dbo.Roles (RoleName, Description)
    VALUES ('Staff', N'Nhân viên chăm sóc');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Family')
    INSERT INTO dbo.Roles (RoleName, Description)
    VALUES ('Family', N'Người nhà');
GO


/* =========================================================
   4. ACCOUNTS
   ========================================================= */

IF OBJECT_ID('dbo.Accounts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Accounts
    (
        AccountId           INT IDENTITY(1,1) PRIMARY KEY,
        RoleId              INT NOT NULL,

        FullName             NVARCHAR(150) NOT NULL,
        Email                NVARCHAR(150) NULL,
        PhoneNumber          NVARCHAR(30) NULL,

        PasswordHash         NVARCHAR(500) NOT NULL,

        Department           NVARCHAR(100) NULL,
        AvatarUrl             NVARCHAR(500) NULL,

        IsActive             BIT NOT NULL DEFAULT 1,

        CreatedAt            DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        UpdatedAt            DATETIME2 NULL,

        CONSTRAINT FK_Accounts_Roles
            FOREIGN KEY (RoleId)
            REFERENCES dbo.Roles(RoleId),

        CONSTRAINT UQ_Accounts_Email
            UNIQUE (Email),

        CONSTRAINT UQ_Accounts_Phone
            UNIQUE (PhoneNumber)
    );
END
GO


/* =========================================================
   5. ROOMS
   ========================================================= */

IF OBJECT_ID('dbo.Rooms', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Rooms
    (
        RoomId              INT IDENTITY(1,1) PRIMARY KEY,

        RoomCode            NVARCHAR(30) NOT NULL UNIQUE,
        RoomName            NVARCHAR(100) NULL,

        FloorNumber         INT NULL,
        Capacity            INT NOT NULL DEFAULT 1,

        Description         NVARCHAR(500) NULL,

        IsActive             BIT NOT NULL DEFAULT 1,

        CreatedAt            DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        CONSTRAINT CK_Rooms_Capacity
            CHECK (Capacity > 0)
    );
END
GO


/* =========================================================
   6. RESIDENTS
   ========================================================= */

IF OBJECT_ID('dbo.Residents', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Residents
    (
        ResidentId          INT IDENTITY(1,1) PRIMARY KEY,

        ResidentCode        NVARCHAR(30) NOT NULL UNIQUE,

        FullName             NVARCHAR(150) NOT NULL,

        DateOfBirth          DATE NULL,
        Age                  INT NULL,

        Gender               NVARCHAR(20) NULL,

        RoomId               INT NULL,

        BloodType            NVARCHAR(5) NULL,

        Status               NVARCHAR(50) NOT NULL
                             DEFAULT N'Đang ổn định',

        AdmissionDate       DATE NULL,

        MedicalHistory      NVARCHAR(MAX) NULL,
        Allergies            NVARCHAR(MAX) NULL,
        Notes                NVARCHAR(MAX) NULL,

        IsActive             BIT NOT NULL DEFAULT 1,

        CreatedAt            DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        UpdatedAt            DATETIME2 NULL,

        CONSTRAINT FK_Residents_Rooms
            FOREIGN KEY (RoomId)
            REFERENCES dbo.Rooms(RoomId),

        CONSTRAINT CK_Residents_Age
            CHECK (Age IS NULL OR Age BETWEEN 0 AND 150)
    );
END
GO


/* =========================================================
   7. FAMILY MEMBERS
   ========================================================= */

IF OBJECT_ID('dbo.FamilyMembers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FamilyMembers
    (
        FamilyMemberId       INT IDENTITY(1,1) PRIMARY KEY,

        ResidentId           INT NOT NULL,

        AccountId            INT NULL,

        FullName             NVARCHAR(150) NOT NULL,

        Relationship         NVARCHAR(50) NULL,

        PhoneNumber          NVARCHAR(30) NULL,
        Email                NVARCHAR(150) NULL,

        Address              NVARCHAR(300) NULL,

        IsPrimaryContact     BIT NOT NULL DEFAULT 0,

        IsActive              BIT NOT NULL DEFAULT 1,

        CreatedAt             DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        CONSTRAINT FK_FamilyMembers_Residents
            FOREIGN KEY (ResidentId)
            REFERENCES dbo.Residents(ResidentId),

        CONSTRAINT FK_FamilyMembers_Accounts
            FOREIGN KEY (AccountId)
            REFERENCES dbo.Accounts(AccountId)
    );
END
GO


/* =========================================================
   8. HEALTH RECORDS
   ========================================================= */

IF OBJECT_ID('dbo.HealthRecords', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HealthRecords
    (
        HealthRecordId       INT IDENTITY(1,1) PRIMARY KEY,

        ResidentId           INT NOT NULL,

        RecordedBy           INT NULL,

        RecordedAt           DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        Systolic             INT NULL,
        Diastolic            INT NULL,

        HeartRate            INT NULL,

        Temperature          DECIMAL(4,1) NULL,

        OxygenSaturation     DECIMAL(5,2) NULL,

        Weight               DECIMAL(6,2) NULL,

        BloodSugar           DECIMAL(6,2) NULL,

        HealthStatus         NVARCHAR(50) NULL,

        Note                 NVARCHAR(MAX) NULL,

        CONSTRAINT FK_HealthRecords_Residents
            FOREIGN KEY (ResidentId)
            REFERENCES dbo.Residents(ResidentId),

        CONSTRAINT FK_HealthRecords_Accounts
            FOREIGN KEY (RecordedBy)
            REFERENCES dbo.Accounts(AccountId)
    );
END
GO


/* =========================================================
   9. HEALTH ALERTS
   ========================================================= */

IF OBJECT_ID('dbo.HealthAlerts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HealthAlerts
    (
        AlertId              INT IDENTITY(1,1) PRIMARY KEY,

        ResidentId           INT NOT NULL,

        HealthRecordId       INT NULL,

        AlertType             NVARCHAR(100) NOT NULL,

        Severity              NVARCHAR(30) NOT NULL
                              DEFAULT N'Thấp',

        Title                 NVARCHAR(255) NOT NULL,

        Message               NVARCHAR(MAX) NULL,

        TriggerValue          NVARCHAR(100) NULL,

        AIRecommendation      NVARCHAR(MAX) NULL,

        Status                NVARCHAR(30) NOT NULL
                              DEFAULT N'Chưa xử lý',

        CreatedAt             DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        ResolvedAt            DATETIME2 NULL,

        CONSTRAINT FK_HealthAlerts_Residents
            FOREIGN KEY (ResidentId)
            REFERENCES dbo.Residents(ResidentId),

        CONSTRAINT FK_HealthAlerts_HealthRecords
            FOREIGN KEY (HealthRecordId)
            REFERENCES dbo.HealthRecords(HealthRecordId)
    );
END
GO


/* =========================================================
   10. ALERT RESOLUTIONS
   ========================================================= */

IF OBJECT_ID('dbo.AlertResolutions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlertResolutions
    (
        ResolutionId         INT IDENTITY(1,1) PRIMARY KEY,

        AlertId              INT NOT NULL,

        ResolvedBy           INT NULL,

        ResolutionType       NVARCHAR(100) NULL,

        ActionTaken          NVARCHAR(MAX) NULL,

        Note                  NVARCHAR(MAX) NULL,

        ResolvedAt            DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        CONSTRAINT FK_AlertResolutions_Alerts
            FOREIGN KEY (AlertId)
            REFERENCES dbo.HealthAlerts(AlertId),

        CONSTRAINT FK_AlertResolutions_Accounts
            FOREIGN KEY (ResolvedBy)
            REFERENCES dbo.Accounts(AccountId)
    );
END
GO


/* =========================================================
   11. MEDICINES
   ========================================================= */

IF OBJECT_ID('dbo.Medicines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Medicines
    (
        MedicineId           INT IDENTITY(1,1) PRIMARY KEY,

        MedicineName         NVARCHAR(200) NOT NULL,

        GenericName          NVARCHAR(200) NULL,

        Description          NVARCHAR(MAX) NULL,

        Manufacturer          NVARCHAR(200) NULL,

        IsActive             BIT NOT NULL DEFAULT 1,

        CreatedAt            DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );
END
GO


/* =========================================================
   12. MEDICATION SCHEDULES
   ========================================================= */

IF OBJECT_ID('dbo.MedicationSchedules', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MedicationSchedules
    (
        MedicationScheduleId INT IDENTITY(1,1) PRIMARY KEY,

        ResidentId           INT NOT NULL,

        MedicineId           INT NOT NULL,

        PrescribedBy         INT NULL,

        Dosage               NVARCHAR(100) NOT NULL,

        Frequency             NVARCHAR(100) NULL,

        StartDate             DATE NOT NULL,

        EndDate               DATE NULL,

        AdministrationTime    TIME NOT NULL,

        Instructions           NVARCHAR(MAX) NULL,

        Status                NVARCHAR(30) NOT NULL
                              DEFAULT N'Đang sử dụng',

        CreatedAt             DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        CONSTRAINT FK_MedicationSchedules_Residents
            FOREIGN KEY (ResidentId)
            REFERENCES dbo.Residents(ResidentId),

        CONSTRAINT FK_MedicationSchedules_Medicines
            FOREIGN KEY (MedicineId)
            REFERENCES dbo.Medicines(MedicineId),

        CONSTRAINT FK_MedicationSchedules_Accounts
            FOREIGN KEY (PrescribedBy)
            REFERENCES dbo.Accounts(AccountId)
    );
END
GO


/* =========================================================
   13. MEDICATION ADMINISTRATIONS
   ========================================================= */

IF OBJECT_ID('dbo.MedicationAdministrations', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MedicationAdministrations
    (
        AdministrationId     INT IDENTITY(1,1) PRIMARY KEY,

        MedicationScheduleId INT NOT NULL,

        AdministeredBy       INT NULL,

        ScheduledDate        DATE NOT NULL,

        ScheduledTime        TIME NOT NULL,

        ActualTime            TIME NULL,

        Status                NVARCHAR(30) NOT NULL
                              DEFAULT N'Chưa thực hiện',

        Note                  NVARCHAR(MAX) NULL,

        CreatedAt             DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        CONSTRAINT FK_MedicationAdministrations_Schedules
            FOREIGN KEY (MedicationScheduleId)
            REFERENCES dbo.MedicationSchedules(MedicationScheduleId),

        CONSTRAINT FK_MedicationAdministrations_Accounts
            FOREIGN KEY (AdministeredBy)
            REFERENCES dbo.Accounts(AccountId)
    );
END
GO


/* =========================================================
   14. CARE SCHEDULES
   ========================================================= */

IF OBJECT_ID('dbo.CareSchedules', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CareSchedules
    (
        CareScheduleId       INT IDENTITY(1,1) PRIMARY KEY,

        ResidentId           INT NOT NULL,

        AssignedStaffId      INT NULL,

        ScheduleName         NVARCHAR(200) NOT NULL,

        ScheduleDate         DATE NOT NULL,

        StartTime             TIME NOT NULL,

        EndTime               TIME NULL,

        ScheduleType         NVARCHAR(50) NOT NULL,

        Status                NVARCHAR(30) NOT NULL
                              DEFAULT N'Chưa thực hiện',

        Note                  NVARCHAR(MAX) NULL,

        CreatedAt             DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        UpdatedAt             DATETIME2 NULL,

        CONSTRAINT FK_CareSchedules_Residents
            FOREIGN KEY (ResidentId)
            REFERENCES dbo.Residents(ResidentId),

        CONSTRAINT FK_CareSchedules_Staff
            FOREIGN KEY (AssignedStaffId)
            REFERENCES dbo.Accounts(AccountId)
    );
END
GO


/* =========================================================
   15. NOTIFICATIONS
   ========================================================= */

IF OBJECT_ID('dbo.Notifications', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Notifications
    (
        NotificationId       INT IDENTITY(1,1) PRIMARY KEY,

        AccountId            INT NOT NULL,

        ResidentId           INT NULL,

        NotificationType     NVARCHAR(50) NULL,

        Title                NVARCHAR(255) NOT NULL,

        Message              NVARCHAR(MAX) NOT NULL,

        IsRead               BIT NOT NULL DEFAULT 0,

        CreatedAt             DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        ReadAt               DATETIME2 NULL,

        CONSTRAINT FK_Notifications_Accounts
            FOREIGN KEY (AccountId)
            REFERENCES dbo.Accounts(AccountId),

        CONSTRAINT FK_Notifications_Residents
            FOREIGN KEY (ResidentId)
            REFERENCES dbo.Residents(ResidentId)
    );
END
GO


/* =========================================================
   16. NOTIFICATION SETTINGS
   ========================================================= */

IF OBJECT_ID('dbo.NotificationSettings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.NotificationSettings
    (
        NotificationSettingId INT IDENTITY(1,1) PRIMARY KEY,

        AccountId             INT NOT NULL UNIQUE,

        EnableHealthAlerts    BIT NOT NULL DEFAULT 1,

        EnableScheduleAlerts  BIT NOT NULL DEFAULT 1,

        EnableMedicationAlerts BIT NOT NULL DEFAULT 1,

        EnableSystemAlerts    BIT NOT NULL DEFAULT 1,

        EnableEmail           BIT NOT NULL DEFAULT 0,

        UpdatedAt             DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

        CONSTRAINT FK_NotificationSettings_Accounts
            FOREIGN KEY (AccountId)
            REFERENCES dbo.Accounts(AccountId)
    );
END
GO


/* =========================================================
   17. INDEXES
   ========================================================= */

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Residents_RoomId'
      AND object_id = OBJECT_ID('dbo.Residents')
)
BEGIN
    CREATE INDEX IX_Residents_RoomId
    ON dbo.Residents(RoomId);
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_HealthRecords_ResidentId'
      AND object_id = OBJECT_ID('dbo.HealthRecords')
)
BEGIN
    CREATE INDEX IX_HealthRecords_ResidentId
    ON dbo.HealthRecords(ResidentId);
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_HealthRecords_RecordedAt'
      AND object_id = OBJECT_ID('dbo.HealthRecords')
)
BEGIN
    CREATE INDEX IX_HealthRecords_RecordedAt
    ON dbo.HealthRecords(RecordedAt);
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_HealthAlerts_ResidentId'
      AND object_id = OBJECT_ID('dbo.HealthAlerts')
)
BEGIN
    CREATE INDEX IX_HealthAlerts_ResidentId
    ON dbo.HealthAlerts(ResidentId);
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_HealthAlerts_Status'
      AND object_id = OBJECT_ID('dbo.HealthAlerts')
)
BEGIN
    CREATE INDEX IX_HealthAlerts_Status
    ON dbo.HealthAlerts(Status);
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_CareSchedules_Date'
      AND object_id = OBJECT_ID('dbo.CareSchedules')
)
BEGIN
    CREATE INDEX IX_CareSchedules_Date
    ON dbo.CareSchedules(ScheduleDate);
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_CareSchedules_ResidentId'
      AND object_id = OBJECT_ID('dbo.CareSchedules')
)
BEGIN
    CREATE INDEX IX_CareSchedules_ResidentId
    ON dbo.CareSchedules(ResidentId);
END
GO


/* =========================================================
   18. SAMPLE ROOMS
   ========================================================= */

IF NOT EXISTS (SELECT 1 FROM dbo.Rooms WHERE RoomCode = '201')
BEGIN
    INSERT INTO dbo.Rooms
    (
        RoomCode,
        RoomName,
        FloorNumber,
        Capacity,
        Description
    )
    VALUES
    (
        '201',
        N'Phòng 201',
        2,
        2,
        N'Phòng chăm sóc người cao tuổi'
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Rooms WHERE RoomCode = '102')
BEGIN
    INSERT INTO dbo.Rooms
    (
        RoomCode,
        RoomName,
        FloorNumber,
        Capacity,
        Description
    )
    VALUES
    (
        '102',
        N'Phòng 102',
        1,
        2,
        N'Phòng chăm sóc người cao tuổi'
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Rooms WHERE RoomCode = '305')
BEGIN
    INSERT INTO dbo.Rooms
    (
        RoomCode,
        RoomName,
        FloorNumber,
        Capacity,
        Description
    )
    VALUES
    (
        '305',
        N'Phòng 305',
        3,
        2,
        N'Phòng chăm sóc người cao tuổi'
    );
END
GO


/* =========================================================
   19. SAMPLE RESIDENTS
   ========================================================= */

IF NOT EXISTS
(
    SELECT 1 FROM dbo.Residents
    WHERE ResidentCode = 'NCT001'
)
BEGIN
    INSERT INTO dbo.Residents
    (
        ResidentCode,
        FullName,
        Age,
        Gender,
        RoomId,
        BloodType,
        Status,
        AdmissionDate,
        MedicalHistory,
        Notes
    )
    SELECT
        'NCT001',
        N'Nguyễn Văn An',
        78,
        N'Nam',
        RoomId,
        'A+',
        N'Đang ổn định',
        '2024-05-15',
        N'Tiền sử huyết áp cao',
        N'Cần theo dõi huyết áp định kỳ'
    FROM dbo.Rooms
    WHERE RoomCode = '201';
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM dbo.Residents
    WHERE ResidentCode = 'NCT002'
)
BEGIN
    INSERT INTO dbo.Residents
    (
        ResidentCode,
        FullName,
        Age,
        Gender,
        RoomId,
        BloodType,
        Status,
        AdmissionDate
    )
    SELECT
        'NCT002',
        N'Lê Văn Bình',
        82,
        N'Nam',
        RoomId,
        'B+',
        N'Cần theo dõi',
        '2024-06-10'
    FROM dbo.Rooms
    WHERE RoomCode = '102';
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM dbo.Residents
    WHERE ResidentCode = 'NCT003'
)
BEGIN
    INSERT INTO dbo.Residents
    (
        ResidentCode,
        FullName,
        Age,
        Gender,
        RoomId,
        BloodType,
        Status,
        AdmissionDate
    )
    SELECT
        'NCT003',
        N'Phạm Thị Cúc',
        75,
        N'Nữ',
        RoomId,
        'O+',
        N'Đang ổn định',
        '2024-07-01'
    FROM dbo.Rooms
    WHERE RoomCode = '305';
END
GO


/* =========================================================
   20. SAMPLE FAMILY MEMBERS
   ========================================================= */

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FamilyMembers FM
    INNER JOIN dbo.Residents R
        ON FM.ResidentId = R.ResidentId
    WHERE R.ResidentCode = 'NCT001'
)
BEGIN
    INSERT INTO dbo.FamilyMembers
    (
        ResidentId,
        FullName,
        Relationship,
        PhoneNumber,
        Address,
        IsPrimaryContact
    )
    SELECT
        ResidentId,
        N'Nguyễn Văn Hải',
        N'Con trai',
        '0909090909',
        N'123 Nguyễn Trãi, Quận 1, TP. HCM',
        1
    FROM dbo.Residents
    WHERE ResidentCode = 'NCT001';
END
GO


IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FamilyMembers FM
    INNER JOIN dbo.Residents R
        ON FM.ResidentId = R.ResidentId
    WHERE R.ResidentCode = 'NCT002'
)
BEGIN
    INSERT INTO dbo.FamilyMembers
    (
        ResidentId,
        FullName,
        Relationship,
        PhoneNumber,
        Address,
        IsPrimaryContact
    )
    SELECT
        ResidentId,
        N'Lê Thị Mai',
        N'Con gái',
        '0918888888',
        N'456 Lê Lợi, Quận Gò Vấp, TP. HCM',
        1
    FROM dbo.Residents
    WHERE ResidentCode = 'NCT002';
END
GO


IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FamilyMembers FM
    INNER JOIN dbo.Residents R
        ON FM.ResidentId = R.ResidentId
    WHERE R.ResidentCode = 'NCT003'
)
BEGIN
    INSERT INTO dbo.FamilyMembers
    (
        ResidentId,
        FullName,
        Relationship,
        PhoneNumber,
        Address,
        IsPrimaryContact
    )
    SELECT
        ResidentId,
        N'Trần Minh Hoàng',
        N'Chồng',
        '0989999999',
        N'789 Cách Mạng Tháng 8, Quận 3, TP. HCM',
        1
    FROM dbo.Residents
    WHERE ResidentCode = 'NCT003';
END
GO


/* =========================================================
   21. SAMPLE MEDICINES
   ========================================================= */

IF NOT EXISTS
(
    SELECT 1 FROM dbo.Medicines
    WHERE MedicineName = N'Paracetamol'
)
BEGIN
    INSERT INTO dbo.Medicines
    (
        MedicineName,
        GenericName,
        Description
    )
    VALUES
    (
        N'Paracetamol',
        N'Paracetamol',
        N'Thuốc giảm đau, hạ sốt'
    );
END
GO


IF NOT EXISTS
(
    SELECT 1 FROM dbo.Medicines
    WHERE MedicineName = N'Amlodipine'
)
BEGIN
    INSERT INTO dbo.Medicines
    (
        MedicineName,
        GenericName,
        Description
    )
    VALUES
    (
        N'Amlodipine',
        N'Amlodipine',
        N'Thuốc điều trị tăng huyết áp'
    );
END
GO


/* =========================================================
   22. VIEWS FOR DASHBOARD
   ========================================================= */

CREATE OR ALTER VIEW dbo.vw_DashboardResidentStatistics
AS
SELECT
    COUNT(*) AS TotalResidents,

    SUM
    (
        CASE
            WHEN Status = N'Đang ổn định'
            THEN 1
            ELSE 0
        END
    ) AS StableResidents,

    SUM
    (
        CASE
            WHEN Status = N'Cần theo dõi'
            THEN 1
            ELSE 0
        END
    ) AS MonitoringResidents,

    SUM
    (
        CASE
            WHEN Status = N'Trung bình'
            THEN 1
            ELSE 0
        END
    ) AS MediumResidents

FROM dbo.Residents
WHERE IsActive = 1;
GO


CREATE OR ALTER VIEW dbo.vw_DashboardAlerts
AS
SELECT
    COUNT(*) AS TotalAlerts,

    SUM
    (
        CASE
            WHEN Status = N'Chưa xử lý'
            THEN 1
            ELSE 0
        END
    ) AS UnresolvedAlerts,

    SUM
    (
        CASE
            WHEN Severity = N'Cao'
            THEN 1
            ELSE 0
        END
    ) AS HighSeverityAlerts

FROM dbo.HealthAlerts;
GO


CREATE OR ALTER VIEW dbo.vw_DashboardMedication
AS
SELECT
    COUNT(*) AS TotalMedicationSchedules,

    SUM
    (
        CASE
            WHEN Status = N'Đang sử dụng'
            THEN 1
            ELSE 0
        END
    ) AS ActiveMedicationSchedules

FROM dbo.MedicationSchedules;
GO


/* =========================================================
   23. VIEW - RESIDENT FULL INFORMATION
   ========================================================= */

CREATE OR ALTER VIEW dbo.vw_ResidentDetails
AS
SELECT
    R.ResidentId,
    R.ResidentCode,
    R.FullName,
    R.DateOfBirth,
    R.Age,
    R.Gender,
    R.BloodType,
    R.Status,
    R.AdmissionDate,
    R.MedicalHistory,
    R.Allergies,
    R.Notes,

    RM.RoomId,
    RM.RoomCode,
    RM.RoomName,

    FM.FamilyMemberId,
    FM.FullName AS FamilyName,
    FM.Relationship AS FamilyRelationship,
    FM.PhoneNumber AS FamilyPhone,
    FM.Email AS FamilyEmail,
    FM.Address AS FamilyAddress

FROM dbo.Residents R

LEFT JOIN dbo.Rooms RM
    ON R.RoomId = RM.RoomId

LEFT JOIN dbo.FamilyMembers FM
    ON R.ResidentId = FM.ResidentId
   AND FM.IsPrimaryContact = 1;
GO


/* =========================================================
   24. VIEW - TODAY CARE SCHEDULE
   ========================================================= */

CREATE OR ALTER VIEW dbo.vw_TodayCareSchedules
AS
SELECT
    CS.CareScheduleId,

    R.ResidentCode,
    R.FullName AS ResidentName,

    RM.RoomCode,

    CS.ScheduleName,
    CS.ScheduleDate,
    CS.StartTime,
    CS.EndTime,

    CS.ScheduleType,
    CS.Status,
    CS.Note,

    A.FullName AS AssignedStaff

FROM dbo.CareSchedules CS

INNER JOIN dbo.Residents R
    ON CS.ResidentId = R.ResidentId

LEFT JOIN dbo.Rooms RM
    ON R.RoomId = RM.RoomId

LEFT JOIN dbo.Accounts A
    ON CS.AssignedStaffId = A.AccountId

WHERE CS.ScheduleDate = CAST(GETDATE() AS DATE);
GO


/* =========================================================
   25. VERIFY DATABASE
   ========================================================= */

SELECT 'Roles' AS TableName, COUNT(*) AS RecordCount
FROM dbo.Roles

UNION ALL

SELECT 'Accounts', COUNT(*)
FROM dbo.Accounts

UNION ALL

SELECT 'Rooms', COUNT(*)
FROM dbo.Rooms

UNION ALL

SELECT 'Residents', COUNT(*)
FROM dbo.Residents

UNION ALL

SELECT 'FamilyMembers', COUNT(*)
FROM dbo.FamilyMembers

UNION ALL

SELECT 'HealthRecords', COUNT(*)
FROM dbo.HealthRecords

UNION ALL

SELECT 'HealthAlerts', COUNT(*)
FROM dbo.HealthAlerts

UNION ALL

SELECT 'AlertResolutions', COUNT(*)
FROM dbo.AlertResolutions

UNION ALL

SELECT 'Medicines', COUNT(*)
FROM dbo.Medicines

UNION ALL

SELECT 'MedicationSchedules', COUNT(*)
FROM dbo.MedicationSchedules

UNION ALL

SELECT 'MedicationAdministrations', COUNT(*)
FROM dbo.MedicationAdministrations

UNION ALL

SELECT 'CareSchedules', COUNT(*)
FROM dbo.CareSchedules

UNION ALL

SELECT 'Notifications', COUNT(*)
FROM dbo.Notifications

UNION ALL

SELECT 'NotificationSettings', COUNT(*)
FROM dbo.NotificationSettings;
GO