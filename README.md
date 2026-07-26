# mrdebian

Autoscript pemasangan **VLESS WebSocket TLS** untuk VPS Debian/Ubuntu yang masih kosong. Skrip memasang Xray-core, Nginx, sijil Let's Encrypt dan menu pengurusan pengguna.

## Fungsi

- Pemasangan VLESS WebSocket dengan TLS
- Sijil SSL Let's Encrypt
- Tambah pengguna dengan tempoh akaun dalam hari
- Padam dan senaraikan pengguna
- Paparkan semula pautan VLESS
- Padam akaun tamat tempoh secara automatik
- Restart Xray dan Nginx melalui menu
- Firewall UFW untuk SSH, HTTP dan HTTPS

## Keperluan

- VPS kosong dengan Ubuntu 22.04/24.04 atau Debian 11/12
- Akses root
- Domain yang rekod DNS A-nya sudah menunjuk ke IP VPS
- Port 22, 80 dan 443 boleh digunakan
- Jika menggunakan Cloudflare, matikan proxy sementara ketika sijil TLS dikeluarkan

## Pemasangan

```bash
apt update && apt install -y wget
wget -O install.sh https://raw.githubusercontent.com/idshan/mrdebian/main/install.sh
chmod +x install.sh
bash install.sh
```

Semasa pemasangan, masukkan domain, email Let's Encrypt, WebSocket path dan address klien/CDN apabila diminta.

## Buka menu

Selepas pemasangan selesai:

```bash
vless-manager
```

Menu menyediakan:

1. Install server dari kosong
2. Add user
3. Delete user
4. List user
5. Papar link user
6. Padam akaun tamat tempoh
7. Restart Xray dan Nginx

## Arahan terus

```bash
vless-manager add
vless-manager delete
vless-manager list
vless-manager link
vless-manager purge
```

## Lokasi konfigurasi

- Data pengguna: `/etc/vless-ws/users.tsv`
- Tetapan server: `/etc/vless-ws/server.env`
- Konfigurasi Xray: `/usr/local/etc/xray/config.json`
- Konfigurasi Nginx: `/etc/nginx/sites-available/vless-ws`

## Perhatian

Skrip ini direka untuk VPS kosong dan boleh menggantikan konfigurasi Nginx/Xray sedia ada. Gunakan hanya pada server milik sendiri atau server yang anda dibenarkan urus.
