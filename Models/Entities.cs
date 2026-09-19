using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SilverCare.Models
{
    [Table("Roles")]
    public class Role
    {
        [Key]
        public int RoleId { get; set; }

        [Required]
        [MaxLength(50)]
        public string RoleName { get; set; } = string.Empty;

        [MaxLength(255)]
        public string? Description { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public virtual ICollection<Account> Accounts { get; set; } = new List<Account>();
    }

    [Table("Accounts")]
    public class Account
    {
        [Key]
        public int AccountId { get; set; }

        [Required]
        public int RoleId { get; set; }

        [ForeignKey("RoleId")]
        public virtual Role? Role { get; set; }

        [Required]
        [MaxLength(150)]
        public string FullName { get; set; } = string.Empty;

        [MaxLength(150)]
        public string? Email { get; set; }

        [MaxLength(30)]
        public string? PhoneNumber { get; set; }

        [Required]
        [MaxLength(500)]
        public string PasswordHash { get; set; } = string.Empty;

        [MaxLength(100)]
        public string? Department { get; set; }

        [MaxLength(500)]
        public string? AvatarUrl { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? UpdatedAt { get; set; }

        public virtual ICollection<FamilyMember> FamilyMembers { get; set; } = new List<FamilyMember>();
        public virtual ICollection<HealthRecord> HealthRecords { get; set; } = new List<HealthRecord>();
        public virtual ICollection<CareSchedule> AssignedSchedules { get; set; } = new List<CareSchedule>();
        public virtual ICollection<Notification> Notifications { get; set; } = new List<Notification>();
        public virtual NotificationSetting? NotificationSetting { get; set; }
    }

    [Table("Rooms")]
    public class Room
    {
        [Key]
        public int RoomId { get; set; }

        [Required]
        [MaxLength(30)]
        public string RoomCode { get; set; } = string.Empty;

        [MaxLength(100)]
        public string? RoomName { get; set; }

        public int? FloorNumber { get; set; }

        public int Capacity { get; set; } = 1;

        [MaxLength(500)]
        public string? Description { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public virtual ICollection<Resident> Residents { get; set; } = new List<Resident>();
    }

    [Table("Residents")]
    public class Resident
    {
        [Key]
        public int ResidentId { get; set; }

        [Required]
        [MaxLength(30)]
        public string ResidentCode { get; set; } = string.Empty;

        [Required]
        [MaxLength(150)]
        public string FullName { get; set; } = string.Empty;

        public DateTime? DateOfBirth { get; set; }

        public int? Age { get; set; }

        [MaxLength(20)]
        public string? Gender { get; set; }

        public int? RoomId { get; set; }

        [ForeignKey("RoomId")]
        public virtual Room? Room { get; set; }

        [MaxLength(5)]
        public string? BloodType { get; set; }

        [Required]
        [MaxLength(50)]
        public string Status { get; set; } = "Đang ổn định";

        public DateTime? AdmissionDate { get; set; }

        public string? MedicalHistory { get; set; }

        public string? Allergies { get; set; }

        public string? Notes { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? UpdatedAt { get; set; }

        public virtual ICollection<FamilyMember> FamilyMembers { get; set; } = new List<FamilyMember>();
        public virtual ICollection<HealthRecord> HealthRecords { get; set; } = new List<HealthRecord>();
        public virtual ICollection<HealthAlert> HealthAlerts { get; set; } = new List<HealthAlert>();
        public virtual ICollection<MedicationSchedule> MedicationSchedules { get; set; } = new List<MedicationSchedule>();
        public virtual ICollection<CareSchedule> CareSchedules { get; set; } = new List<CareSchedule>();
        public virtual ICollection<Notification> Notifications { get; set; } = new List<Notification>();
    }

    [Table("FamilyMembers")]
    public class FamilyMember
    {
        [Key]
        public int FamilyMemberId { get; set; }

        public int ResidentId { get; set; }

        [ForeignKey("ResidentId")]
        public virtual Resident? Resident { get; set; }

        public int? AccountId { get; set; }

        [ForeignKey("AccountId")]
        public virtual Account? Account { get; set; }

        [Required]
        [MaxLength(150)]
        public string FullName { get; set; } = string.Empty;

        [MaxLength(50)]
        public string? Relationship { get; set; }

        [MaxLength(30)]
        public string? PhoneNumber { get; set; }

        [MaxLength(150)]
        public string? Email { get; set; }

        [MaxLength(300)]
        public string? Address { get; set; }

        public bool IsPrimaryContact { get; set; } = false;

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    [Table("HealthRecords")]
    public class HealthRecord
    {
        [Key]
        public int HealthRecordId { get; set; }

        public int ResidentId { get; set; }

        [ForeignKey("ResidentId")]
        public virtual Resident? Resident { get; set; }

        public int? RecordedBy { get; set; }

        [ForeignKey("RecordedBy")]
        public virtual Account? StaffAccount { get; set; }

        public DateTime RecordedAt { get; set; } = DateTime.UtcNow;

        public int? Systolic { get; set; }

        public int? Diastolic { get; set; }

        public int? HeartRate { get; set; }

        [Column(TypeName = "decimal(4,1)")]
        public decimal? Temperature { get; set; }

        [Column(TypeName = "decimal(5,2)")]
        public decimal? OxygenSaturation { get; set; }

        [Column(TypeName = "decimal(6,2)")]
        public decimal? Weight { get; set; }

        [Column(TypeName = "decimal(6,2)")]
        public decimal? BloodSugar { get; set; }

        [MaxLength(50)]
        public string? HealthStatus { get; set; }

        public string? Note { get; set; }

        public virtual ICollection<HealthAlert> HealthAlerts { get; set; } = new List<HealthAlert>();
    }

    [Table("HealthAlerts")]
    public class HealthAlert
    {
        [Key]
        public int AlertId { get; set; }

        public int ResidentId { get; set; }

        [ForeignKey("ResidentId")]
        public virtual Resident? Resident { get; set; }

        public int? HealthRecordId { get; set; }

        [ForeignKey("HealthRecordId")]
        public virtual HealthRecord? HealthRecord { get; set; }

        [Required]
        [MaxLength(100)]
        public string AlertType { get; set; } = string.Empty;

        [Required]
        [MaxLength(30)]
        public string Severity { get; set; } = "Thấp";

        [Required]
        [MaxLength(255)]
        public string Title { get; set; } = string.Empty;

        public string? Message { get; set; }

        [MaxLength(100)]
        public string? TriggerValue { get; set; }

        public string? AIRecommendation { get; set; }

        [Required]
        [MaxLength(30)]
        public string Status { get; set; } = "Chưa xử lý";

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? ResolvedAt { get; set; }

        public virtual ICollection<AlertResolution> AlertResolutions { get; set; } = new List<AlertResolution>();
    }

    [Table("AlertResolutions")]
    public class AlertResolution
    {
        [Key]
        public int ResolutionId { get; set; }

        public int AlertId { get; set; }

        [ForeignKey("AlertId")]
        public virtual HealthAlert? HealthAlert { get; set; }

        public int? ResolvedBy { get; set; }

        [ForeignKey("ResolvedBy")]
        public virtual Account? StaffAccount { get; set; }

        [MaxLength(100)]
        public string? ResolutionType { get; set; }

        public string? ActionTaken { get; set; }

        public string? Note { get; set; }

        public DateTime ResolvedAt { get; set; } = DateTime.UtcNow;
    }

    [Table("Medicines")]
    public class Medicine
    {
        [Key]
        public int MedicineId { get; set; }

        [Required]
        [MaxLength(200)]
        public string MedicineName { get; set; } = string.Empty;

        [MaxLength(200)]
        public string? GenericName { get; set; }

        public string? Description { get; set; }

        [MaxLength(200)]
        public string? Manufacturer { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public virtual ICollection<MedicationSchedule> MedicationSchedules { get; set; } = new List<MedicationSchedule>();
    }

    [Table("MedicationSchedules")]
    public class MedicationSchedule
    {
        [Key]
        public int MedicationScheduleId { get; set; }

        public int ResidentId { get; set; }

        [ForeignKey("ResidentId")]
        public virtual Resident? Resident { get; set; }

        public int MedicineId { get; set; }

        [ForeignKey("MedicineId")]
        public virtual Medicine? Medicine { get; set; }

        public int? PrescribedBy { get; set; }

        [ForeignKey("PrescribedBy")]
        public virtual Account? DoctorAccount { get; set; }

        [Required]
        [MaxLength(100)]
        public string Dosage { get; set; } = string.Empty;

        [MaxLength(100)]
        public string? Frequency { get; set; }

        public DateTime StartDate { get; set; }

        public DateTime? EndDate { get; set; }

        public TimeSpan AdministrationTime { get; set; }

        public string? Instructions { get; set; }

        [Required]
        [MaxLength(30)]
        public string Status { get; set; } = "Đang sử dụng";

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public virtual ICollection<MedicationAdministration> MedicationAdministrations { get; set; } = new List<MedicationAdministration>();
    }

    [Table("MedicationAdministrations")]
    public class MedicationAdministration
    {
        [Key]
        public int AdministrationId { get; set; }

        public int MedicationScheduleId { get; set; }

        [ForeignKey("MedicationScheduleId")]
        public virtual MedicationSchedule? MedicationSchedule { get; set; }

        public int? AdministeredBy { get; set; }

        [ForeignKey("AdministeredBy")]
        public virtual Account? StaffAccount { get; set; }

        public DateTime ScheduledDate { get; set; }

        public TimeSpan ScheduledTime { get; set; }

        public TimeSpan? ActualTime { get; set; }

        [Required]
        [MaxLength(30)]
        public string Status { get; set; } = "Chưa thực hiện";

        public string? Note { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    [Table("CareSchedules")]
    public class CareSchedule
    {
        [Key]
        public int CareScheduleId { get; set; }

        public int ResidentId { get; set; }

        [ForeignKey("ResidentId")]
        public virtual Resident? Resident { get; set; }

        public int? AssignedStaffId { get; set; }

        [ForeignKey("AssignedStaffId")]
        public virtual Account? AssignedStaff { get; set; }

        [Required]
        [MaxLength(200)]
        public string ScheduleName { get; set; } = string.Empty;

        public DateTime ScheduleDate { get; set; }

        public TimeSpan StartTime { get; set; }

        public TimeSpan? EndTime { get; set; }

        [Required]
        [MaxLength(50)]
        public string ScheduleType { get; set; } = string.Empty;

        [Required]
        [MaxLength(30)]
        public string Status { get; set; } = "Chưa thực hiện";

        public string? Note { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? UpdatedAt { get; set; }
    }

    [Table("Notifications")]
    public class Notification
    {
        [Key]
        public int NotificationId { get; set; }

        public int AccountId { get; set; }

        [ForeignKey("AccountId")]
        public virtual Account? Account { get; set; }

        public int? ResidentId { get; set; }

        [ForeignKey("ResidentId")]
        public virtual Resident? Resident { get; set; }

        [MaxLength(50)]
        public string? NotificationType { get; set; }

        [Required]
        [MaxLength(255)]
        public string Title { get; set; } = string.Empty;

        [Required]
        public string Message { get; set; } = string.Empty;

        public bool IsRead { get; set; } = false;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? ReadAt { get; set; }
    }

    [Table("NotificationSettings")]
    public class NotificationSetting
    {
        [Key]
        public int NotificationSettingId { get; set; }

        public int AccountId { get; set; }

        [ForeignKey("AccountId")]
        public virtual Account? Account { get; set; }

        public bool EnableHealthAlerts { get; set; } = true;

        public bool EnableScheduleAlerts { get; set; } = true;

        public bool EnableMedicationAlerts { get; set; } = true;

        public bool EnableSystemAlerts { get; set; } = true;

        public bool EnableEmail { get; set; } = false;

        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
