# PowerShell Script to fix connectivity for Smart Laundry App
# Run this as Administrator

$DashboardPort = 5000
$ApiPort = 5001
$mDNSPort = 5353

echo ">>> SMART LAUNDRY CONNECTIVITY FIXER <<<"
echo ""

# 1. Open TCP Port 5000 (Dashboard)
echo "[1/3] Membuka Port TCP $DashboardPort (Dashboard)..."
New-NetFirewallRule -DisplayName "Smart Laundry Dashboard" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $DashboardPort -ErrorAction SilentlyContinue

# 2. Open TCP Port 5001 (API)
echo "[2/3] Membuka Port TCP $ApiPort (API Server)..."
New-NetFirewallRule -DisplayName "Smart Laundry API" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $ApiPort -ErrorAction SilentlyContinue

# 3. Open UDP Port 5353 (mDNS / Zeroconf)
echo "[3/3] Membuka Port UDP $mDNSPort (mDNS/Hostname Access)..."
New-NetFirewallRule -DisplayName "mDNS/Zeroconf Discovery" -Direction Inbound -Action Allow -Protocol UDP -LocalPort $mDNSPort -ErrorAction SilentlyContinue

echo ""
echo ">>> SELESAI! <<<"
echo "Silakan coba akses kembali dari device lain menggunakan:"
echo "http://$($env:COMPUTERNAME).local:$DashboardPort"
echo ""
pause
