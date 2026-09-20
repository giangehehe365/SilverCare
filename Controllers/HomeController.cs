using Microsoft.AspNetCore.Mvc;
using SilverCare.Models;
using System.Diagnostics;

namespace SilverCare.Controllers
{
    // Xác thực và phân quyền thật nằm ở Supabase Auth + Row Level Security
    // (xem wwwroot/js/auth-guard.js và supabase/schema.sql). Controller này
    // chỉ còn nhiệm vụ chọn đúng View — không còn giữ trạng thái đăng nhập
    // bằng ASP.NET Session.
    public class HomeController : Controller
    {
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

        [HttpGet]
        public IActionResult Family()
        {
            return View();
        }

        [HttpGet]
        public IActionResult Logout()
        {
            // Đăng xuất thật (sb.auth.signOut()) chạy phía client trong auth-guard.js.
            return RedirectToAction("Index", "Home");
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Dashboard()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Residents()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Health()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Schedule()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Profile(string? tab = "profile")
        {
            // Lưu hồ sơ cá nhân (bảng profiles) chạy thẳng phía client qua supabase-js,
            // không cần postback về controller.
            ViewBag.ActiveTab = tab ?? "profile";
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Medicine()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Report()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult Notifications()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult UserManagement()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult SystemSettings()
        {
            return View();
        }

        [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
        [HttpGet]
        public IActionResult AccessDenied(string? feature)
        {
            ViewBag.FeatureName = string.IsNullOrEmpty(feature) ? "Chức năng được yêu cầu" : feature;
            return View();
        }

        public IActionResult LoginSuccess(string role)
        {
            ViewBag.Role = role;
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }
}
