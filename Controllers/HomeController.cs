using Microsoft.AspNetCore.Mvc;
using System.Net.Http;
using System.Text.Json;
using System.Text;
using System.Threading.Tasks;

namespace SilverCare.Controllers
{
    public class HomeController : Controller
    {
        private readonly HttpClient _httpClient;

        // Constructor injecting HttpClient
        public HomeController(HttpClient httpClient)
        {
            _httpClient = httpClient;
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
            var loginRequest = new { Username = username, Password = password };
            var jsonContent = new StringContent(JsonSerializer.Serialize(loginRequest), Encoding.UTF8, "application/json");

            try
            {
                var response = await _httpClient.PostAsync("http://localhost:5100/api/auth/login-staff", jsonContent);
                if (response.IsSuccessStatusCode)
                {
                    var responseString = await response.Content.ReadAsStringAsync();
                    var loginResponse = JsonSerializer.Deserialize<LoginResponseModel>(responseString, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                    
                    var fullName = loginResponse?.FullName ?? "Nguyễn Văn A";
                    var role = loginResponse?.Role ?? "Nhân viên";

                    HttpContext.Session.SetString("IsLoggedIn", "true");
                    HttpContext.Session.SetString("FullName", fullName);
                    HttpContext.Session.SetString("Role", role);

                    TempData["FullName"] = fullName;
                    TempData["Role"] = role;

                    return RedirectToAction("Dashboard");
                }
            }
            catch (HttpRequestException)
            {
                ViewBag.Error = "Không thể kết nối đến máy chủ Backend. Vui lòng thử lại sau.";
                return View();
            }

            ViewBag.Error = "Email hoặc mật khẩu không hợp lệ, vui lòng nhập lại";
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
            var loginRequest = new { Username = username, Password = password };
            var jsonContent = new StringContent(JsonSerializer.Serialize(loginRequest), Encoding.UTF8, "application/json");

            try
            {
                var response = await _httpClient.PostAsync("http://localhost:5100/api/auth/login-family", jsonContent);
                if (response.IsSuccessStatusCode)
                {
                    var responseString = await response.Content.ReadAsStringAsync();
                    var loginResponse = JsonSerializer.Deserialize<LoginResponseModel>(responseString, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                    
                    var fullName = loginResponse?.FullName ?? "Nguyễn Văn Hải";
                    var role = loginResponse?.Role ?? "Người nhà";

                    HttpContext.Session.SetString("IsLoggedIn", "true");
                    HttpContext.Session.SetString("FullName", fullName);
                    HttpContext.Session.SetString("Role", role);

                    TempData["FullName"] = fullName;
                    TempData["Role"] = role;

                    return RedirectToAction("Dashboard");
                }
            }
            catch (HttpRequestException)
            {
                ViewBag.Error = "Không thể kết nối đến máy chủ Backend. Vui lòng thử lại sau.";
                return View();
            }

            ViewBag.Error = "Email hoặc mật khẩu không hợp lệ, vui lòng nhập lại";
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
        public IActionResult Dashboard()
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
        public IActionResult Profile(string? tab = "profile")
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            var fullName = HttpContext.Session.GetString("FullName") ?? "Nguyễn Thị Lan";
            var role = HttpContext.Session.GetString("Role") ?? "Nhân viên";
            
            TempData["FullName"] = fullName;
            TempData["Role"] = role;

            ViewBag.FullName = fullName;
            ViewBag.Role = role;
            ViewBag.ActiveTab = tab ?? "profile";

            // Determine email, phone, department based on user
            if (fullName == "Nguyễn Văn A" || fullName == "Nguyễn Thị Lan")
            {
                ViewBag.Email = fullName == "Nguyễn Văn A" ? "a.nguyen@silvercare.vn" : "ntlan@silvercare.vn";
                ViewBag.Phone = "0901 234 567";
                ViewBag.Department = "Phòng chăm sóc A";
            }
            else if (fullName == "Trần Thị B")
            {
                ViewBag.Email = "b.tran@silvercare.vn";
                ViewBag.Phone = "0912 345 678";
                ViewBag.Department = "Phòng chăm sóc B";
            }
            else if (fullName == "Lê Hoàng C")
            {
                ViewBag.Email = "c.le@silvercare.vn";
                ViewBag.Phone = "0987 654 321";
                ViewBag.Department = "Phòng chăm sóc C";
            }
            else if (role == "Người nhà")
            {
                ViewBag.Email = "example@email.com";
                ViewBag.Phone = "0909 090 909";
                ViewBag.Department = "Thân nhân cư dân";
            }
            else
            {
                ViewBag.Email = "ntlan@silvercare.vn";
                ViewBag.Phone = "0901 234 567";
                ViewBag.Department = "Phòng chăm sóc A";
            }

            return View();
        }

        [HttpPost]
        public IActionResult Profile(string fullName, string email, string phone, string department, string? tab = "profile")
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString("IsLoggedIn")))
            {
                return RedirectToAction("Index", "Home");
            }

            if (!string.IsNullOrEmpty(fullName))
            {
                HttpContext.Session.SetString("FullName", fullName);
                TempData["FullName"] = fullName;
            }

            var role = HttpContext.Session.GetString("Role") ?? "Nhân viên";
            TempData["Role"] = role;

            ViewBag.FullName = fullName;
            ViewBag.Role = role;
            ViewBag.Email = email;
            ViewBag.Phone = phone;
            ViewBag.Department = department;
            ViewBag.ActiveTab = tab ?? "profile";
            ViewBag.SuccessMessage = "Lưu thay đổi thông tin cá nhân thành công!";

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

        private class LoginResponseModel
        {
            public bool IsSuccess { get; set; }
            public string Message { get; set; } = string.Empty;
            public string FullName { get; set; } = string.Empty;
            public string Role { get; set; } = string.Empty;
        }
    }
}

