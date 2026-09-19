using System.Security.Cryptography;
using System.Text;

namespace SilverCare.Helpers
{
    public static class PasswordHelper
    {
        public static string HashPassword(string password)
        {
            if (string.IsNullOrEmpty(password)) return string.Empty;
            using var sha256 = SHA256.Create();
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(password));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public static bool VerifyPassword(string inputPassword, string storedHash)
        {
            if (string.IsNullOrEmpty(inputPassword) || string.IsNullOrEmpty(storedHash))
                return false;

            // Direct match (for plain text test data in DB)
            if (inputPassword == storedHash)
                return true;

            // SHA256 match
            var inputHash = HashPassword(inputPassword);
            if (string.Equals(inputHash, storedHash, StringComparison.OrdinalIgnoreCase))
                return true;

            return false;
        }
    }
}
