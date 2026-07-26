# mrdebian

Autoscript pemasangan dan pengurusan **VLESS WebSocket TLS** untuk VPS Debian/Ubuntu yang masih kosong. Skrip memasang Xray-core, Nginx, sijil SSL Let's Encrypt, firewall dan menu pengurusan akaun.

## Pemasangan pantas

Jalankan sebagai `root` pada VPS kosong:

```bash
apt update && apt install -y wget
wget -O install.sh https://raw.githubusercontent.com/idshan/mrdebian/main/install.sh
chmod +x install.sh
bash install.sh
```

Atau satu baris:

```bash
wget -O install.sh https://raw.githubusercontent.com/idshan/mrdebian/main/install.sh && chmod +x install.sh && bash install.sh
```

## Keperluan

- VPS kosong dengan Ubuntu 22.04/24.04 atau Debian 11/12
- Akses `root`
- Domain atau subdomain sendiri
- Rekod DNS `A` domain menunjuk ke IP awam VPS
- Port TCP 22, 80 dan 443 dibuka pada firewall/panel VPS
- Tiada Nginx, Apache atau Xray penting yang perlu dikekalkan

> Jika menggunakan Cloudflare, gunakan `DNS only` (awan kelabu) semasa Let's Encrypt mengeluarkan sijil. Proxy boleh dihidupkan semula selepas pemasangan berjaya.

## Maklumat yang diminta semasa pemasangan

1. Domain untuk TLS, contohnya `vpn.example.com`
2. Email Let's Encrypt (boleh dibiarkan kosong)
3. WebSocket path, lalai `/vless`
4. Address klien/CDN, lalai menggunakan domain
5. Pengesahan sebelum perubahan dibuat

Selepas pemasangan, skrip meminta nama pengguna dan tempoh akaun dalam hari, kemudian memaparkan pautan `vless://` untuk diimport ke aplikasi klien.

## Fungsi utama

- VLESS WebSocket dengan TLS pada port 443
- TLS ditamatkan oleh Nginx
- Xray hanya mendengar pada `127.0.0.1:10000`
- Sijil Let's Encrypt dan pembaharuan automatik Certbot
- UUID berasingan untuk setiap pengguna
- Tempoh akaun berdasarkan bilangan hari
- Pembersihan akaun tamat tempoh setiap hari
- Firewall UFW membuka OpenSSH, port 80 dan 443
- Halaman web asas sebagai penyamaran pada laluan `/`

## Menu pengurusan

Buka menu selepas pemasangan:

```bash
vless-manager
```

Pilihan menu:

```text
Selepas pemasangan:

1. Add User
2. Delete User
3. List User
4. Papar Link User
5. Padam Akaun Tamat Tempoh
6. Restart Service
0. Keluar
```

## Arahan terus

Menu juga boleh dipanggil tanpa membuka paparan utama:

```bash
vless-manager add       # Tambah pengguna dan tetapkan bilangan hari
vless-manager delete    # Padam pengguna
vless-manager list      # Senaraikan pengguna dan tarikh tamat
vless-manager link      # Paparkan semula pautan pengguna
vless-manager purge     # Padam semua akaun yang telah tamat
```

## Aplikasi klien

Pautan VLESS boleh diimport ke aplikasi yang menyokong VLESS WebSocket TLS, contohnya:

- v2rayNG
- Hiddify
- NekoBox
- Shadowrocket

Tetapan yang dihasilkan menggunakan `security=tls`, `type=ws`, domain sebagai SNI/WS Host dan path yang dipilih semasa pemasangan.

## Lokasi fail penting

| Kegunaan | Lokasi |
|---|---|
| Database pengguna | `/etc/vless-ws/users.tsv` |
| Tetapan domain/server | `/etc/vless-ws/server.env` |
| Konfigurasi Xray | `/usr/local/etc/xray/config.json` |
| Konfigurasi Nginx | `/etc/nginx/sites-available/vless-ws` |
| Program menu | `/usr/local/sbin/vless-manager` |
| Jadual pembersihan akaun | `/etc/cron.d/vless-expiry` |

## Pemeriksaan servis

```bash
systemctl status xray --no-pager
systemctl status nginx --no-pager
nginx -t
certbot certificates
```

Jika sijil gagal dikeluarkan, pastikan domain sudah menunjuk ke IP VPS, port 80 boleh dicapai dan proxy Cloudflare dimatikan sementara.

## Perhatian

Skrip ini direka untuk **VPS kosong**. Ia boleh menggantikan konfigurasi Nginx dan Xray sedia ada. Gunakan hanya pada server milik sendiri atau server yang anda dibenarkan urus. Simpan pautan dan UUID pengguna dengan selamat.
