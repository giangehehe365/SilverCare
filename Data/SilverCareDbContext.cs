using Microsoft.EntityFrameworkCore;
using SilverCare.Models;

namespace SilverCare.Data
{
    public class SilverCareDbContext : DbContext
    {
        public SilverCareDbContext(DbContextOptions<SilverCareDbContext> options)
            : base(options)
        {
        }

        public DbSet<Role> Roles => Set<Role>();
        public DbSet<Account> Accounts => Set<Account>();
        public DbSet<Room> Rooms => Set<Room>();
        public DbSet<Resident> Residents => Set<Resident>();
        public DbSet<FamilyMember> FamilyMembers => Set<FamilyMember>();
        public DbSet<HealthRecord> HealthRecords => Set<HealthRecord>();
        public DbSet<HealthAlert> HealthAlerts => Set<HealthAlert>();
        public DbSet<AlertResolution> AlertResolutions => Set<AlertResolution>();
        public DbSet<Medicine> Medicines => Set<Medicine>();
        public DbSet<MedicationSchedule> MedicationSchedules => Set<MedicationSchedule>();
        public DbSet<MedicationAdministration> MedicationAdministrations => Set<MedicationAdministration>();
        public DbSet<CareSchedule> CareSchedules => Set<CareSchedule>();
        public DbSet<Notification> Notifications => Set<Notification>();
        public DbSet<NotificationSetting> NotificationSettings => Set<NotificationSetting>();

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Accounts
            modelBuilder.Entity<Account>()
                .HasIndex(a => a.Email)
                .IsUnique()
                .HasFilter("[Email] IS NOT NULL");

            modelBuilder.Entity<Account>()
                .HasIndex(a => a.PhoneNumber)
                .IsUnique()
                .HasFilter("[PhoneNumber] IS NOT NULL");

            modelBuilder.Entity<Account>()
                .HasOne(a => a.Role)
                .WithMany(r => r.Accounts)
                .HasForeignKey(a => a.RoleId)
                .OnDelete(DeleteBehavior.Restrict);

            // Rooms
            modelBuilder.Entity<Room>()
                .HasIndex(r => r.RoomCode)
                .IsUnique();

            // Residents
            modelBuilder.Entity<Resident>()
                .HasIndex(r => r.ResidentCode)
                .IsUnique();

            modelBuilder.Entity<Resident>()
                .HasOne(r => r.Room)
                .WithMany(rm => rm.Residents)
                .HasForeignKey(r => r.RoomId)
                .OnDelete(DeleteBehavior.SetNull);

            // FamilyMembers
            modelBuilder.Entity<FamilyMember>()
                .HasOne(f => f.Resident)
                .WithMany(r => r.FamilyMembers)
                .HasForeignKey(f => f.ResidentId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<FamilyMember>()
                .HasOne(f => f.Account)
                .WithMany(a => a.FamilyMembers)
                .HasForeignKey(f => f.AccountId)
                .OnDelete(DeleteBehavior.SetNull);

            // HealthRecords
            modelBuilder.Entity<HealthRecord>()
                .HasOne(h => h.Resident)
                .WithMany(r => r.HealthRecords)
                .HasForeignKey(h => h.ResidentId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<HealthRecord>()
                .HasOne(h => h.StaffAccount)
                .WithMany(a => a.HealthRecords)
                .HasForeignKey(h => h.RecordedBy)
                .OnDelete(DeleteBehavior.SetNull);

            // HealthAlerts
            modelBuilder.Entity<HealthAlert>()
                .HasOne(a => a.Resident)
                .WithMany(r => r.HealthAlerts)
                .HasForeignKey(a => a.ResidentId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<HealthAlert>()
                .HasOne(a => a.HealthRecord)
                .WithMany(h => h.HealthAlerts)
                .HasForeignKey(a => a.HealthRecordId)
                .OnDelete(DeleteBehavior.SetNull);

            // AlertResolutions
            modelBuilder.Entity<AlertResolution>()
                .HasOne(ar => ar.HealthAlert)
                .WithMany(ha => ha.AlertResolutions)
                .HasForeignKey(ar => ar.AlertId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<AlertResolution>()
                .HasOne(ar => ar.StaffAccount)
                .WithMany()
                .HasForeignKey(ar => ar.ResolvedBy)
                .OnDelete(DeleteBehavior.SetNull);

            // MedicationSchedules
            modelBuilder.Entity<MedicationSchedule>()
                .HasOne(ms => ms.Resident)
                .WithMany(r => r.MedicationSchedules)
                .HasForeignKey(ms => ms.ResidentId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<MedicationSchedule>()
                .HasOne(ms => ms.Medicine)
                .WithMany(m => m.MedicationSchedules)
                .HasForeignKey(ms => ms.MedicineId)
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<MedicationSchedule>()
                .HasOne(ms => ms.DoctorAccount)
                .WithMany()
                .HasForeignKey(ms => ms.PrescribedBy)
                .OnDelete(DeleteBehavior.SetNull);

            // MedicationAdministrations
            modelBuilder.Entity<MedicationAdministration>()
                .HasOne(ma => ma.MedicationSchedule)
                .WithMany(ms => ms.MedicationAdministrations)
                .HasForeignKey(ma => ma.MedicationScheduleId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<MedicationAdministration>()
                .HasOne(ma => ma.StaffAccount)
                .WithMany()
                .HasForeignKey(ma => ma.AdministeredBy)
                .OnDelete(DeleteBehavior.SetNull);

            // CareSchedules
            modelBuilder.Entity<CareSchedule>()
                .HasOne(cs => cs.Resident)
                .WithMany(r => r.CareSchedules)
                .HasForeignKey(cs => cs.ResidentId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<CareSchedule>()
                .HasOne(cs => cs.AssignedStaff)
                .WithMany(a => a.AssignedSchedules)
                .HasForeignKey(cs => cs.AssignedStaffId)
                .OnDelete(DeleteBehavior.SetNull);

            // Notifications
            modelBuilder.Entity<Notification>()
                .HasOne(n => n.Account)
                .WithMany(a => a.Notifications)
                .HasForeignKey(n => n.AccountId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<Notification>()
                .HasOne(n => n.Resident)
                .WithMany(r => r.Notifications)
                .HasForeignKey(n => n.ResidentId)
                .OnDelete(DeleteBehavior.SetNull);

            // NotificationSettings
            modelBuilder.Entity<NotificationSetting>()
                .HasOne(ns => ns.Account)
                .WithOne(a => a.NotificationSetting)
                .HasForeignKey<NotificationSetting>(ns => ns.AccountId)
                .OnDelete(DeleteBehavior.Cascade);
        }
    }
}
