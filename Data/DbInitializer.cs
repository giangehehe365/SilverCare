using Microsoft.EntityFrameworkCore;
using SilverCare.Helpers;
using SilverCare.Models;

namespace SilverCare.Data
{
    public static class DbInitializer
    {
        public static async Task InitializeAsync(IServiceProvider serviceProvider)
        {
            using var scope = serviceProvider.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<SilverCareDbContext>();

            try
            {
                // Ensure Database and schema are created if not existing
                await context.Database.EnsureCreatedAsync();

                // 1. Roles
                if (!await context.Roles.AnyAsync())
                {
                    context.Roles.AddRange(
                        new Role { RoleName = "Admin", Description = "Quản trị hệ thống", IsActive = true },
                        new Role { RoleName = "Manager", Description = "Quản lý trung tâm", IsActive = true },
                        new Role { RoleName = "Staff", Description = "Nhân viên chăm sóc", IsActive = true },
                        new Role { RoleName = "Family", Description = "Người nhà", IsActive = true }
                    );
                    await context.SaveChangesAsync();
                }

                var adminRole = await context.Roles.FirstOrDefaultAsync(r => r.RoleName == "Admin");
                var staffRole = await context.Roles.FirstOrDefaultAsync(r => r.RoleName == "Staff");
                var familyRole = await context.Roles.FirstOrDefaultAsync(r => r.RoleName == "Family");
                var managerRole = await context.Roles.FirstOrDefaultAsync(r => r.RoleName == "Manager");

                // 2. Accounts
                if (!await context.Accounts.AnyAsync())
                {
                    var defaultHash = PasswordHelper.HashPassword("123456");

                    var adminAccount = new Account
                    {
                        RoleId = adminRole?.RoleId ?? 1,
                        FullName = "Quản Trị Viên",
                        Email = "admin@silvercare.vn",
                        PhoneNumber = "0900000001",
                        PasswordHash = defaultHash,
                        Department = "Ban Quản Trị",
                        IsActive = true,
                        CreatedAt = DateTime.UtcNow
                    };

                    var staffAccount = new Account
                    {
                        RoleId = staffRole?.RoleId ?? 3,
                        FullName = "Nguyễn Thị Lan",
                        Email = "staff@silvercare.vn",
                        PhoneNumber = "0901234567",
                        PasswordHash = defaultHash,
                        Department = "Phòng chăm sóc A",
                        IsActive = true,
                        CreatedAt = DateTime.UtcNow
                    };

                    var familyAccount = new Account
                    {
                        RoleId = familyRole?.RoleId ?? 4,
                        FullName = "Nguyễn Văn Hải",
                        Email = "family@silvercare.vn",
                        PhoneNumber = "0909090909",
                        PasswordHash = defaultHash,
                        Department = "Thân nhân cư dân",
                        IsActive = true,
                        CreatedAt = DateTime.UtcNow
                    };

                    context.Accounts.AddRange(adminAccount, staffAccount, familyAccount);
                    await context.SaveChangesAsync();
                }

                // 3. Rooms
                if (!await context.Rooms.AnyAsync())
                {
                    context.Rooms.AddRange(
                        new Room { RoomCode = "201", RoomName = "Phòng 201", FloorNumber = 2, Capacity = 2, Description = "Phòng chăm sóc người cao tuổi" },
                        new Room { RoomCode = "102", RoomName = "Phòng 102", FloorNumber = 1, Capacity = 2, Description = "Phòng chăm sóc người cao tuổi" },
                        new Room { RoomCode = "305", RoomName = "Phòng 305", FloorNumber = 3, Capacity = 2, Description = "Phòng chăm sóc người cao tuổi" }
                    );
                    await context.SaveChangesAsync();
                }

                var room201 = await context.Rooms.FirstOrDefaultAsync(r => r.RoomCode == "201");
                var room102 = await context.Rooms.FirstOrDefaultAsync(r => r.RoomCode == "102");
                var room305 = await context.Rooms.FirstOrDefaultAsync(r => r.RoomCode == "305");

                // 4. Residents
                if (!await context.Residents.AnyAsync())
                {
                    context.Residents.AddRange(
                        new Resident
                        {
                            ResidentCode = "NCT001",
                            FullName = "Nguyễn Văn An",
                            Age = 78,
                            Gender = "Nam",
                            RoomId = room201?.RoomId,
                            BloodType = "A+",
                            Status = "Đang ổn định",
                            AdmissionDate = new DateTime(2024, 5, 15),
                            MedicalHistory = "Tiền sử huyết áp cao",
                            Notes = "Cần theo dõi huyết áp định kỳ",
                            IsActive = true
                        },
                        new Resident
                        {
                            ResidentCode = "NCT002",
                            FullName = "Lê Văn Bình",
                            Age = 82,
                            Gender = "Nam",
                            RoomId = room102?.RoomId,
                            BloodType = "B+",
                            Status = "Cần theo dõi",
                            AdmissionDate = new DateTime(2024, 6, 10),
                            MedicalHistory = "Tiểu đường tuýp 2, Tim mạch nhẹ",
                            Notes = "Hạn chế đồ ngọt",
                            IsActive = true
                        },
                        new Resident
                        {
                            ResidentCode = "NCT003",
                            FullName = "Phạm Thị Cúc",
                            Age = 75,
                            Gender = "Nữ",
                            RoomId = room305?.RoomId,
                            BloodType = "O+",
                            Status = "Đang ổn định",
                            AdmissionDate = new DateTime(2024, 7, 1),
                            MedicalHistory = "Viêm khớp mãn tính",
                            Notes = "Hỗ trợ đi lại buổi sáng",
                            IsActive = true
                        }
                    );
                    await context.SaveChangesAsync();
                }

                // 5. Family Members
                var resident1 = await context.Residents.FirstOrDefaultAsync(r => r.ResidentCode == "NCT001");
                var resident2 = await context.Residents.FirstOrDefaultAsync(r => r.ResidentCode == "NCT002");
                var familyAcc = await context.Accounts.FirstOrDefaultAsync(a => a.Email == "family@silvercare.vn");

                if (!await context.FamilyMembers.AnyAsync() && resident1 != null)
                {
                    context.FamilyMembers.AddRange(
                        new FamilyMember
                        {
                            ResidentId = resident1.ResidentId,
                            AccountId = familyAcc?.AccountId,
                            FullName = "Nguyễn Văn Hải",
                            Relationship = "Con trai",
                            PhoneNumber = "0909090909",
                            Email = "family@silvercare.vn",
                            Address = "123 Nguyễn Trãi, Quận 1, TP. HCM",
                            IsPrimaryContact = true,
                            IsActive = true
                        },
                        new FamilyMember
                        {
                            ResidentId = resident2?.ResidentId ?? resident1.ResidentId,
                            FullName = "Lê Thị Mai",
                            Relationship = "Con gái",
                            PhoneNumber = "0918888888",
                            Address = "456 Lê Lợi, Quận Gò Vấp, TP. HCM",
                            IsPrimaryContact = true,
                            IsActive = true
                        }
                    );
                    await context.SaveChangesAsync();
                }

                // 6. Medicines
                if (!await context.Medicines.AnyAsync())
                {
                    context.Medicines.AddRange(
                        new Medicine { MedicineName = "Paracetamol 500mg", GenericName = "Paracetamol", Description = "Thuốc giảm đau, hạ sốt", Manufacturer = "Dược Hậu Giang" },
                        new Medicine { MedicineName = "Amlodipine 5mg", GenericName = "Amlodipine", Description = "Thuốc điều trị tăng huyết áp", Manufacturer = "Pfizer" },
                        new Medicine { MedicineName = "Metformin 500mg", GenericName = "Metformin", Description = "Thuốc hạ đường huyết", Manufacturer = "Sanofi" }
                    );
                    await context.SaveChangesAsync();
                }

                // 7. Care Schedules & Health Records
                var staffAcc = await context.Accounts.FirstOrDefaultAsync(a => a.Email == "staff@silvercare.vn");
                if (!await context.HealthRecords.AnyAsync() && resident1 != null)
                {
                    context.HealthRecords.Add(new HealthRecord
                    {
                        ResidentId = resident1.ResidentId,
                        RecordedBy = staffAcc?.AccountId,
                        RecordedAt = DateTime.UtcNow,
                        Systolic = 120,
                        Diastolic = 80,
                        HeartRate = 75,
                        Temperature = 36.6m,
                        OxygenSaturation = 98.0m,
                        BloodSugar = 5.6m,
                        HealthStatus = "Bình thường",
                        Note = "Sức khỏe ổn định"
                    });
                    await context.SaveChangesAsync();
                }

                // 8. Notifications
                if (!await context.Notifications.AnyAsync() && staffAcc != null)
                {
                    context.Notifications.AddRange(
                        new Notification
                        {
                            AccountId = staffAcc.AccountId,
                            ResidentId = resident1?.ResidentId,
                            NotificationType = "Health",
                            Title = "Đo huyết áp định kỳ",
                            Message = "Đã hoàn thành kiểm tra huyết áp buổi sáng cho cư dân Nguyễn Văn An.",
                            IsRead = false,
                            CreatedAt = DateTime.UtcNow
                        },
                        new Notification
                        {
                            AccountId = staffAcc.AccountId,
                            NotificationType = "System",
                            Title = "Chào mừng bạn đến với SilverCare",
                            Message = "Hệ thống kết nối cơ sở dữ liệu SQL Server thành công.",
                            IsRead = false,
                            CreatedAt = DateTime.UtcNow
                        }
                    );
                    await context.SaveChangesAsync();
                }
            }
            catch (Exception ex)
            {
                var logger = scope.ServiceProvider.GetService<ILogger<SilverCareDbContext>>();
                logger?.LogError(ex, "Lỗi xảy ra trong quá trình khởi tạo dữ liệu mẫu CSDL.");
            }
        }
    }
}
