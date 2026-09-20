var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Không còn dùng ASP.NET Session/HttpClient cho đăng nhập — xác thực và phiên
// làm việc do Supabase Auth quản lý phía client (xem wwwroot/js/auth-guard.js).
builder.Services.AddControllersWithViews();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
