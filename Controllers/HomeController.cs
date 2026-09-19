using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SilverCare.Data;
using SilverCare.Helpers;
using SilverCare.Models;

namespace SilverCare.Controllers
{
    public class HomeController : Controller
    {
        private readonly SilverCareDbContext _dbContext;

        public HomeController(SilverCareDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Index()
        {
            return View();
        }

        [HttpGet]
        public IActionResult Staff()
        {
            return View();
        }

        [HttpPost]
        public async Task<IActionResult> Staff(string username, string password)
        {
            if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password))
            {
                ViewBag.Error = "Vui lòng nhập đầy đủ tài khoản và mật khẩu.";
                return View();
            }

            try
            {
                var user = await _dbContext.Accounts
                    .Include(a => a.Role)
                    .FirstOrDefaultAsync(a => 
                        (a.Email == username || a.PhoneNumber == username) && a.IsActive);

                if (user != null)
                {
                    // Allow Admin, Manager, and Staff roles
                    if (user.Role?.RoleName == "Staff" || user.Role?.RoleName == "Admin" || user.Role?.RoleName == "Manager")
                    {
                        if (PasswordHelper.VerifyPassword(password, user.PasswordHash))
                        {
                            var fullName = user.FullName;
                            var role = user.Role.RoleName switch
                            {
                                "Admin" => "Admin",
                                "Manager" => "Quản lý",
                                "Staff" => "Nhân viên",
                                _ => user.Role.RoleName
                            };

                            HttpContext.Session.SetString("IsLoggedIn", "true");
                            HttpContext.Session.SetInt32("AccountId", user.AccountId);
                            HttpContext.Session.SetString("FullName", fullName);
                            HttpContext.Session.SetString("Role", role);
                            HttpContext.Session.SetString("Email", user.Email ?? "");

                            TempData["FullName"] = fullName;
                            TempData["Role"] = role;

                            return RedirectToAction("Dashboard");
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                ViewBag.Error = "Không thể kết nối đến cơ sở dữ liệu SQL Server: " + ex.Message;
                return View();
            }

            ViewBag.Error = "Email/Số điện thoại hoặc mật khẩu không hợp lệ, vui lòng nhập lại";
            return View();
        }

        [HttpGet]
        public IActionResult Family()
        {
            return View();
        }

        [HttpPost]
        public async Task<IActionResult> Family(string username, string password)
        {
            if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password))
            {
                ViewBag.Error = "Vui lòng nhập đầy đủ tài khoản và mật khẩu.";
                return View();
            }

            try
            {
                var user = await _dbContext.Accounts
                    .Include(a => a.Role)
                    .FirstOrDefaultAsync(a => 
                        (a.Email == username || a.PhoneNumber == username) && a.IsActive);

                if (user != null)
                {
                    // Allow Family and Admin
                    if (user.Role?.RoleName == "Family" || user.Role?.RoleName == "Admin")
                    {
                        if (PasswordHelper.VerifyPassword(password, user.PasswordHash))
                        {
                            var fullName = user.FullName;
                            var role = user.Role.RoleName == "Admin" ? "Admin" : "Người nhà";

                            HttpContext.Session.SetString("IsLoggedIn", "true");
                            HttpContext.Session.SetInt32("AccountId", user.AccountId);
                            HttpContext.Session.SetString("FullName", fullName);
                            HttpContext.Session.SetString("Role", role);
                            HttpContext.Session.SetString("Email", user.Email ?? "");

                            TempData["FullName"] = fullName;
                            TempData["Role"] = role;

                            return RedirectToAction("Dashboard");
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                ViewBag.Error = "Không thể kết nối đến cơ sở dữ liệu SQL Server: " + ex.Message;
                return View();
            }

            ViewBag.Error = "Email/Số điện thoại hoặc mật khẩu không hợp lệ, vui lòng nhập lại";
            return View();
        }

        [HttpGet]
        public IActionResult Logout()
        {
            HttpContext.Session.Clear();
            TempData.Clear();
            Response.Cookies.Delete(".AspNetCore.Session");

            Response.Headers["Cache-Control"] = "no-cache, no-store, must-revalidate";
            Response.Headers["Pragma"] = "no-cache";
            Response.Headers["Expires"] = "0";

            return RedirectToAction("Index", "Home");
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public async Task<IActionResult> Dashboard()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName");
            var role = HttpContext.Session.GetString("Role");
            if (!string.IsNullOrEmpty(fullName)) TempData["FullName"] = fullName;
            if (!string.IsNullOrEmpty(role)) TempData["Role"] = role;

            try
            {
                ViewBag.TotalResidents = await _dbContext.Residents.CountAsync(r => r.IsActive);
                ViewBag.StableResidents = await _dbContext.Residents.CountAsync(r => r.IsActive && r.Status == "Đang ổn định");
                ViewBag.MonitoringResidents = await _dbContext.Residents.CountAsync(r => r.IsActive && r.Status == "Cần theo dõi");
                ViewBag.TotalAlerts = await _dbContext.HealthAlerts.CountAsync(a => a.Status == "Chưa xử lý");
            }
            catch
            {
                // Fallback if DB query fails
            }

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Residents()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName");
            var role = HttpContext.Session.GetString("Role");
            if (!string.IsNullOrEmpty(fullName)) TempData["FullName"] = fullName;
            if (!string.IsNullOrEmpty(role)) TempData["Role"] = role;

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Health()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName");
            var role = HttpContext.Session.GetString("Role");
            if (!string.IsNullOrEmpty(fullName)) TempData["FullName"] = fullName;
            if (!string.IsNullOrEmpty(role)) TempData["Role"] = role;

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Schedule()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName");
            var role = HttpContext.Session.GetString("Role");
            if (!string.IsNullOrEmpty(fullName)) TempData["FullName"] = fullName;
            if (!string.IsNullOrEmpty(role)) TempData["Role"] = role;

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public async Task<IActionResult> Profile(string? tab = "profile")
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var accountId = HttpContext.Session.GetInt32("AccountId");
            Account? account = null;

            if (accountId.HasValue)
            {
                account = await _dbContext.Accounts.Include(a => a.Role).FirstOrDefaultAsync(a => a.AccountId == accountId.Value);
            }
            if (account == null)
            {
                var sessionEmail = HttpContext.Session.GetString("Email");
                if (!string.IsNullOrEmpty(sessionEmail))
                {
                    account = await _dbContext.Accounts.Include(a => a.Role).FirstOrDefaultAsync(a => a.Email == sessionEmail);
                }
            }

            var fullName = account?.FullName ?? HttpContext.Session.GetString("FullName") ?? "Nguyễn Thị Lan";
            var role = account?.Role?.RoleName ?? HttpContext.Session.GetString("Role") ?? "Nhân viên";
            var email = account?.Email ?? "ntlan@silvercare.vn";
            var phone = account?.PhoneNumber ?? "0901 234 567";
            var department = account?.Department ?? "Phòng chăm sóc A";

            TempData["FullName"] = fullName;
            TempData["Role"] = role;

            ViewBag.FullName = fullName;
            ViewBag.Role = role;
            ViewBag.Email = email;
            ViewBag.Phone = phone;
            ViewBag.Department = department;
            ViewBag.ActiveTab = tab ?? "profile";

            return View();
        }

        [HttpPost]
        public async Task<IActionResult> Profile(string fullName, string email, string phone, string department, string? tab = "profile")
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var accountId = HttpContext.Session.GetInt32("AccountId");
            Account? account = null;

            if (accountId.HasValue)
            {
                account = await _dbContext.Accounts.FirstOrDefaultAsync(a => a.AccountId == accountId.Value);
            }
            if (account == null)
            {
                var sessionEmail = HttpContext.Session.GetString("Email");
                if (!string.IsNullOrEmpty(sessionEmail))
                {
                    account = await _dbContext.Accounts.FirstOrDefaultAsync(a => a.Email == sessionEmail);
                }
            }

            if (account != null)
            {
                account.FullName = fullName;
                account.Email = email;
                account.PhoneNumber = phone;
                account.Department = department;
                account.UpdatedAt = DateTime.UtcNow;
                await _dbContext.SaveChangesAsync();
            }

            if (!string.IsNullOrEmpty(fullName))
            {
                HttpContext.Session.SetString("FullName", fullName);
                TempData["FullName"] = fullName;
            }

            if (!string.IsNullOrEmpty(email))
            {
                HttpContext.Session.SetString("Email", email);
            }

            var role = HttpContext.Session.GetString("Role") ?? "Nhân viên";
            TempData["Role"] = role;

            ViewBag.FullName = fullName;
            ViewBag.Role = role;
            ViewBag.Email = email;
            ViewBag.Phone = phone;
            ViewBag.Department = department;
            ViewBag.ActiveTab = tab ?? "profile";
            ViewBag.SuccessMessage = "Lưu thay đổi thông tin cá nhân vào cơ sở dữ liệu thành công!";

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Medicine()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName");
            var role = HttpContext.Session.GetString("Role");
            if (!string.IsNullOrEmpty(fullName)) TempData["FullName"] = fullName;
            if (!string.IsNullOrEmpty(role)) TempData["Role"] = role;

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Report()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName");
            var role = HttpContext.Session.GetString("Role");
            if (!string.IsNullOrEmpty(fullName)) TempData["FullName"] = fullName;
            if (!string.IsNullOrEmpty(role)) TempData["Role"] = role;

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Notifications()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName");
            var role = HttpContext.Session.GetString("Role");
            if (!string.IsNullOrEmpty(fullName)) TempData["FullName"] = fullName;
            if (!string.IsNullOrEmpty(role)) TempData["Role"] = role;

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult UserManagement()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var role = HttpContext.Session.GetString("Role") ?? "Nhân viên";
            if (role != "Admin")
            {
                return RedirectToAction("AccessDenied", "Home", new { feature = "Quản lý tài khoản người dùng" });
            }

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult SystemSettings()
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var role = HttpContext.Session.GetString("Role") ?? "Nhân viên";
            if (role != "Admin")
            {
                return RedirectToAction("AccessDenied", "Home", new { feature = "Cấu hình hệ thống" });
            }

            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult AccessDenied(string? feature)
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName") ?? "Nguyễn Thị Lan";
            var role = HttpContext.Session.GetString("Role") ?? "Nhân viên";
            TempData["FullName"] = fullName;
            TempData["Role"] = role;

            ViewBag.FeatureName = string.IsNullOrEmpty(feature) ? "Chức năng được yêu cầu" : feature;
            ViewBag.Role = role;
            ViewBag.FullName = fullName;

            return View();
        }

        public IActionResult LoginSuccess(string role)
        {
            ViewBag.Role = role;
            return View();
        }
    }
}
