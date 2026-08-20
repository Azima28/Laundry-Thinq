# Analisis Klasifikasi Elemen: Wajib vs Opsional, Statis vs Dinamis

> Berdasarkan reverse-engineering `LAPORAN PKL NIKEN FIXED.docx` (60 halaman, 553 paragraf) + koreksi dari screenshot Daftar Isi dan Cover.

---

## Legenda Klasifikasi

| Label | Arti |
|-------|------|
| 🔴 **WAJIB** | Harus selalu ada di setiap laporan |
| 🟡 **OPSIONAL** | Boleh ada, boleh tidak (tergantung data yang tersedia) |
| 🟢 **STATIS** | Konten tetap/bawaan sistem, TIDAK perlu diinput user |
| 🔵 **DINAMIS** | Konten berubah sesuai input user / diekstrak AI dari cerita |
| 🤖 **AI-GEN** | Di-generate oleh AI berdasarkan cerita pengalaman |

---

## COVER LUAR & COVER DALAM

| Elemen | Klasifikasi | Sumber Data | Catatan |
|--------|-------------|-------------|---------|
| "LAPORAN" | 🔴 WAJIB 🟢 STATIS | Hardcoded | Selalu sama |
| "PRAKTEK KERJA LAPANGAN (PKL)" | 🔴 WAJIB 🟢 STATIS | Hardcoded | Selalu sama |
| "DI [NAMA PERUSAHAAN]" | 🔴 WAJIB 🔵 DINAMIS | Input user (perusahaan.nama) | Auto uppercase |
| Subtitle "Disusun untuk memenuhi..." | 🔴 WAJIB 🟢 STATIS | Template + jurusan siswa | Hanya jurusan yang berubah |
| "disusun oleh :" | 🔴 WAJIB 🟢 STATIS | Hardcoded | |
| Nama Siswa (Bold Underline) | 🔴 WAJIB 🔵 DINAMIS | Input user (siswa.nama) | **Font: Arial 16pt** bukan TNR! |
| **Logo SMKN4** (image1.jpeg) | 🔴 WAJIB 🟢 STATIS | Bawaan sistem (`smkn4_assets/image1.jpeg`) | Ukuran: ~6.16cm × 4.87cm, posisi antara nama & NIS |
| "NIS. [NOMOR]" | 🔴 WAJIB 🔵 DINAMIS | Input user (siswa.nis) | Di bawah logo, bukan di samping nama |
| **Logo Provinsi Lampung** (image2.png) | 🔴 WAJIB 🟢 STATIS | Bawaan sistem (`smkn4_assets/image2.png`) | Ukuran: ~2.70cm × 3.88cm, anchor di samping kiri teks kop |
| Kop: "PEMERINTAH PROVINSI LAMPUNG" | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 | |
| Kop: "DINAS PENDIDIKAN DAN KEBUDAYAAN" | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 | |
| Kop: "SMK NEGERI 4 BANDAR LAMPUNG" | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 | Bold |
| Kop: Alamat + Telp + Fax | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 | |
| Kop: Kelurahan + Kota | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 | |
| Kop: Email + Website | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 | |
| Kop: NPSN + NSS | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 | |

> [!NOTE]
> **Cover Dalam IDENTIK dengan Cover Luar** — dihasilkan otomatis, user tidak perlu input 2x.

---

## HALAMAN PENGESAHAN INDUSTRI

| Elemen | Klasifikasi | Sumber Data |
|--------|-------------|-------------|
| "HALAMAN PENGESAHAN" | 🔴 WAJIB 🟢 STATIS | Hardcoded |
| "PADA [PERUSAHAAN]" | 🔴 WAJIB 🔵 DINAMIS | perusahaan.nama |
| "Menyetujui," | 🔴 WAJIB 🟢 STATIS | Hardcoded |
| Label "Pembimbing Industri I" | 🔴 WAJIB 🟢 STATIS | Hardcoded |
| Nama Pembimbing Industri | 🔴 WAJIB 🔵 DINAMIS | Input user (perusahaan.pembimbing_industri.nama) |
| Label jabatan pimpinan (misal "Kepala Cabang") | 🔴 WAJIB 🔵 DINAMIS | Input user (perusahaan.pimpinan.jabatan) |
| Nama Pimpinan | 🔴 WAJIB 🔵 DINAMIS | Input user (perusahaan.pimpinan.nama) |

---

## HALAMAN PENGESAHAN SEKOLAH

| Elemen | Klasifikasi | Sumber Data |
|--------|-------------|-------------|
| "PADA SMK NEGERI 4 BANDAR LAMPUNG" | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 |
| Nama Ketua KK + NIP | 🔴 WAJIB 🔵 DINAMIS | Input user (sekolah.ketua_kk) |
| Nama Pembimbing + NIP | 🔴 WAJIB 🔵 DINAMIS | Input user (sekolah.pembimbing_sekolah) |
| Nama Waka Humas + NIP | 🔴 WAJIB 🔵 DINAMIS | Input user (sekolah.waka_humas) |

> [!IMPORTANT]
> Data guru (Ketua KK, Pembimbing, Waka Humas) **WAJIB diisi user** karena berbeda setiap siswa/angkatan. Tapi kita bisa **pre-fill** dengan data default SMKN4 terkini yang bisa diedit user.

---

## IDENTITAS SISWA

| Field | Klasifikasi | Sumber Data |
|-------|-------------|-------------|
| Nama Siswa | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Nomor Induk / NISN | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Tempat, Tgl Lahir | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Jenis Kelamin | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Golongan Darah | 🟡 OPSIONAL 🔵 DINAMIS | Input user (boleh "-") |
| Catatan Kesehatan | 🟡 OPSIONAL 🔵 DINAMIS | Input user (boleh "-") |
| No. Telp/Hp Siswa | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Nama Sekolah | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 |
| Alamat Sekolah | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 |
| No. Telp Sekolah | 🔴 WAJIB 🟢 STATIS | Hardcoded SMKN4 |
| Nama Orang Tua/Wali | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Alamat Orang Tua/Wali | 🔴 WAJIB 🔵 DINAMIS | Input user |
| No. Telp Orang Tua/Wali | 🔴 WAJIB 🔵 DINAMIS | Input user |
| **Pas Foto Siswa** (3×4) | 🔴 WAJIB 🔵 DINAMIS | Upload user | 
| TTD "Yang Bersangkutan," | 🔴 WAJIB 🟢 STATIS | Template |

---

## IDENTITAS INDUSTRI / INSTANSI

| Field | Klasifikasi | Sumber Data |
|-------|-------------|-------------|
| **Perusahaan / Instansi** (header) | 🔴 WAJIB 🟢 STATIS | Hardcoded label |
| Nama Perusahaan | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Alamat Perusahaan | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Bidang Produk/Jasa | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Status (PMDN/PMA/dll) | 🟡 OPSIONAL 🔵 DINAMIS | Input user (boleh "-") |
| Nomor Telp | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Nomor Fax | 🟡 OPSIONAL 🔵 DINAMIS | Input user (boleh "-") |
| E-mail | 🟡 OPSIONAL 🔵 DINAMIS | Input user (boleh "-") |
| Website | 🟡 OPSIONAL 🔵 DINAMIS | Input user (boleh "-") |
| **Pimpinan** (header) | 🔴 WAJIB 🟢 STATIS | Hardcoded label |
| Jabatan Pimpinan | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Nama Pimpinan | 🔴 WAJIB 🔵 DINAMIS | Input user |
| **HRD / Ka. Tu** (header) | 🟡 OPSIONAL 🟢 STATIS | Tidak semua perusahaan punya |
| Nama HRD | 🟡 OPSIONAL 🔵 DINAMIS | Input user |
| Telp HRD | 🟡 OPSIONAL 🔵 DINAMIS | Input user |
| Email HRD | 🟡 OPSIONAL 🔵 DINAMIS | Input user |
| **Pembimbing** (header) | 🔴 WAJIB 🟢 STATIS | Hardcoded label |
| Jabatan Pembimbing | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Nama Pembimbing | 🔴 WAJIB 🔵 DINAMIS | Input user |
| Telp Pembimbing | 🟡 OPSIONAL 🔵 DINAMIS | Input user |
| Email Pembimbing | 🟡 OPSIONAL 🔵 DINAMIS | Input user |

---

## KATA PENGANTAR

| Elemen | Klasifikasi | Sumber Data |
|--------|-------------|-------------|
| Ucapan syukur (paragraf 1) | 🔴 WAJIB 🟢 STATIS | Template default (bisa diedit) |
| Paragraf tujuan laporan | 🔴 WAJIB 🟢 STATIS | Template default |
| Hierarki terima kasih: | | |
| — Tuhan YME | 🔴 WAJIB 🟢 STATIS | Template |
| — Kedua Orang Tua | 🔴 WAJIB 🟢 STATIS | Template |
| — Pembimbing Industri (nama) | 🔴 WAJIB 🔵 DINAMIS | Diambil dari perusahaan.pembimbing_industri.nama |
| — Kepala Sekolah (nama) | 🔴 WAJIB 🔵 DINAMIS | Diambil dari sekolah.kepala_sekolah.nama |
| — Ketua Jurusan (nama) | 🔴 WAJIB 🔵 DINAMIS | Diambil dari sekolah.ketua_kk.nama |
| — Pembimbing Sekolah (nama) | 🔴 WAJIB 🔵 DINAMIS | Diambil dari sekolah.pembimbing_sekolah.nama |
| — "Pihak lain..." | 🔴 WAJIB 🟢 STATIS | Template |
| Paragraf harapan | 🔴 WAJIB 🟢 STATIS | Template default |
| Tanggal + Kota | 🔴 WAJIB 🔵 DINAMIS | Input user (tanggal selesai laporan) |
| TTD + nama "Penulis" | 🔴 WAJIB 🔵 DINAMIS | siswa.nama |

---

## DAFTAR ISI

| Elemen | Klasifikasi | Sumber Data |
|--------|-------------|-------------|
| "DAFTAR ISI" heading | 🔴 WAJIB 🟢 STATIS | Hardcoded |
| Entri front matter (Pengesahan, Identitas, dll) | 🔴 WAJIB 🟢 STATIS | Auto-generate dari struktur |
| Entri BAB I-VI + sub-bab | 🔴 WAJIB 🔵 DINAMIS | Auto-generate berdasarkan BAB yang aktif |
| Nomor halaman | 🔴 WAJIB 🔵 DINAMIS | Placeholder (user isi manual di Word) atau TOC field |

> [!TIP]
> Idealnya kita generate **Word TOC field** yang bisa di-update otomatis saat user buka di Word. Jika terlalu rumit, fallback ke format teks dengan placeholder halaman.

---

## BAB I — PENDAHULUAN

| Sub-bab | Klasifikasi | Sumber Data | Catatan |
|---------|-------------|-------------|---------|
| **1.1 Latar Belakang** | 🔴 WAJIB 🟢 STATIS + 🔵 DINAMIS | Template + jurusan + nama perusahaan | Paragraf template, variabel = nama perusahaan & jurusan |
| **1.2 Tujuan Kegiatan PKL** | 🔴 WAJIB 🟢 STATIS | Template 9 poin | Selalu sama (dari dokumen Niken) |
| **1.3 Sejarah Singkat [Perusahaan]** | 🔴 WAJIB 🔵 DINAMIS | Input user / AI-generate dari cerita | Beda tiap perusahaan |
| — a) Visi dan Misi | 🟡 OPSIONAL 🔵 DINAMIS | Input user / AI-generate | Tidak semua perusahaan punya visi-misi yang diketahui siswa |
| — b) Profil Lokasi PKL | 🟡 OPSIONAL 🔵 DINAMIS | Input user / AI-generate | Bisa hanya 1 alamat, beda dari Niken yang punya banyak cabang |
| **1.4 Tata Tertib Perusahaan** | 🟡 OPSIONAL 🔵 DINAMIS | Input user / AI-generate | Tidak semua siswa tahu tata tertib detailnya |
| — a) Waktu Kerja | 🟡 OPSIONAL 🔵 DINAMIS | Input user / AI-generate | Kalau ada → render tabel jadwal |
| — b) Tata Tertib Karyawan | 🟡 OPSIONAL 🔵 DINAMIS | Input user / AI-generate | Berupa poin-poin |
| **1.5 Bagan Struktur Organisasi** | 🟡 OPSIONAL 🔵 DINAMIS | Upload gambar user | Tidak semua siswa punya gambar bagan |
| **1.6 Job Description** | 🟡 OPSIONAL 🔵 DINAMIS | Input user / AI-generate | Jumlah posisi **SANGAT DINAMIS** — bisa 1 posisi, bisa 10+ |

> [!IMPORTANT]
> **BAB I adalah bagian PALING DINAMIS** di seluruh laporan. Perusahaan kecil (warung/bengkel) mungkin hanya punya 1 jabatan tanpa visi-misi. Perusahaan besar (bank/finance) bisa punya 10+ jabatan dengan bagan struktur detail. **Sistem harus bisa menangani keduanya.**

**Aturan dinamis BAB I:**
- Sub-bab 1.1 dan 1.2 → **SELALU ADA** (wajib, template statis)
- Sub-bab 1.3 → **SELALU ADA** (wajib), tapi isinya dinamis — minimal 1 paragraf
- Sub-bab 1.3a (Visi Misi) → Muncul **HANYA JIKA** user memberikan data visi/misi
- Sub-bab 1.3b (Profil Lokasi) → Muncul **HANYA JIKA** ada data lokasi selain alamat utama
- Sub-bab 1.4 → Muncul **HANYA JIKA** ada data tata tertib / jadwal kerja
- Sub-bab 1.5 → Muncul **HANYA JIKA** user upload gambar bagan
- Sub-bab 1.6 → Muncul **HANYA JIKA** ada data job description (min 1 posisi)

**Penomoran sub-bab OTOMATIS menyesuaikan!** Jika Visi Misi dihilangkan, maka Tata Tertib menjadi 1.4 (bukan 1.5).

---

## BAB II — KEGIATAN INDUSTRI

| Sub-bab | Klasifikasi | Sumber Data | Catatan |
|---------|-------------|-------------|---------|
| **2.1 Proses Kegiatan selama PKL** | 🔴 WAJIB 🔵 DINAMIS | AI-generate dari cerita | |
| — Intro paragraf (tempat ditempatkan + durasi) | 🔴 WAJIB 🔵 DINAMIS | Input user (divisi, durasi) + 🤖 AI-GEN | |
| — Daftar divisi/bidang | 🔵 DINAMIS | 🤖 AI-GEN dari cerita | Bisa 1 divisi, bisa 5+ |
| — Poin tugas per divisi | 🔵 DINAMIS | 🤖 AI-GEN dari cerita | Poin-poin **singkat** (1 kalimat per tugas) |

> [!NOTE]
> BAB II hanya berisi **ringkasan poin-poin singkat** per divisi. Elaborasi detail ada di BAB IV.
> 
> **Contoh Niken:** 2 divisi (Operation = 10 tugas, Collection = 10 tugas).
> **Contoh warung:** 1 divisi (Operasional = 3-5 tugas).
> 
> Jumlah divisi dan tugas **sepenuhnya dinamis** berdasarkan cerita user.

---

## BAB III — TINJAUAN PUSTAKA

| Sub-bab | Klasifikasi | Sumber Data | Catatan |
|---------|-------------|-------------|---------|
| **3.1 Landasan Teori** | 🔴 WAJIB 🟢 STATIS | Template | Definisi PKL, selalu sama |
| **3.2 Asas PKL (Referensi Hukum)** | 🔴 WAJIB 🟢 STATIS | Template 17 poin | UU No.20/2003, PP 29/1990, Kepmendikbud, Permendikbud No.50/2020, dll |
| **3.3 Sejarah SMKN 4 Bandar Lampung** | 🔴 WAJIB 🟢 STATIS | Hardcoded `smkn4_sejarah.py` | Selalu sama untuk semua siswa SMKN4 |

> BAB III adalah **BAB paling statis** — hampir 100% template. User tidak perlu input apa-apa.

---

## BAB IV — DATA PENGAMATAN

| Sub-bab | Klasifikasi | Sumber Data | Catatan |
|---------|-------------|-------------|---------|
| **4.1 Pelaksanaan Kegiatan PKL di Tempat Kerja** | 🔴 WAJIB 🔵 DINAMIS | 🤖 AI-GEN dari cerita | |
| — Intro paragraf (durasi, tempat) | 🔴 WAJIB 🔵 DINAMIS | Input user + AI | |
| — Detail kegiatan 1 (judul bold + elaborasi) | 🔴 WAJIB 🔵 DINAMIS | 🤖 AI-GEN dari cerita | Elaborasi **panjang** (bisa 2-3 paragraf per kegiatan) |
| — Detail kegiatan 2... | 🔵 DINAMIS | 🤖 AI-GEN | Jumlah kegiatan dinamis |
| — Tabel perhitungan (jika relevan) | 🟡 OPSIONAL 🔵 DINAMIS | 🤖 AI-GEN | Niken punya 2 tabel keuangan, tapi ini spesifik Akuntansi |
| **4.2 Jenis Peralatan & Perlengkapan Kantor** | 🟡 OPSIONAL 🔵 DINAMIS | 🤖 AI-GEN + Upload foto | |
| — Daftar peralatan (judul bold + gambar + caption + deskripsi) | 🟡 OPSIONAL 🔵 DINAMIS | 🤖 AI-GEN + Upload | Niken: 4 alat (Printer, Komputer, Alat Tulis, Stempel) |

> [!IMPORTANT]
> **Peralatan bersifat OPSIONAL** tapi sangat **menambah ketebalan laporan**.
> - Siswa RPL (programmer) → peralatan: Laptop, Mouse, Monitor, dll
> - Siswa Akuntansi → peralatan: Printer, Komputer, Alat Tulis, Stempel
> - Siswa di warung kecil → mungkin tidak punya peralatan kantor signifikan
> 
> Jika user upload foto peralatan, sub-bab ini otomatis muncul. Jika tidak ada foto, sub-bab ini di-skip.

---

## BAB V — PEMBAHASAN

| Sub-bab | Klasifikasi | Sumber Data | Catatan |
|---------|-------------|-------------|---------|
| **5.1 Hal-hal yang Perlu Diperhatikan** | 🔴 WAJIB 🔵 DINAMIS | 🤖 AI-GEN dari cerita | Refleksi pengalaman: apa yang dirasakan, pelajaran, insight |

> BAB V di Niken **SANGAT PENDEK** — hanya 3 paragraf refleksi. TANPA sub-bab hambatan/solusi.
> Konten di-generate AI berdasarkan cerita pengalaman user.

---

## BAB VI — KESIMPULAN DAN SARAN

| Sub-bab | Klasifikasi | Sumber Data | Catatan |
|---------|-------------|-------------|---------|
| **6.1 Kesimpulan** | 🔴 WAJIB 🔵 DINAMIS | 🤖 AI-GEN + Template | 2 paragraf |
| **6.2 Saran** | 🔴 WAJIB 🔵 DINAMIS | 🤖 AI-GEN + Template | 2 poin: 1 untuk sekolah, 1 untuk perusahaan |

---

## DAFTAR PUSTAKA

| Elemen | Klasifikasi | Sumber Data | Catatan |
|--------|-------------|-------------|---------|
| Referensi-referensi | 🔴 WAJIB 🟢 STATIS + 🔵 DINAMIS | Template + AI | Template: referensi UU, website sekolah. Dinamis: website perusahaan, sumber lain dari cerita |

> Niken punya **9 referensi** — campuran website perusahaan, website sekolah, undang-undang, dan buku. Kita bisa auto-generate beberapa referensi default + tambahkan referensi spesifik perusahaan.

---

## LAMPIRAN

| Elemen | Klasifikasi | Sumber Data | Catatan |
|--------|-------------|-------------|---------|
| Heading "LAMPIRAN" | 🔴 WAJIB 🟢 STATIS | Hardcoded |
| Foto-foto kegiatan + caption | 🟡 OPSIONAL 🔵 DINAMIS | Upload user | Niken: 10 foto. User bisa upload 0-20 foto |
| Margin section lampiran khusus | 🔴 WAJIB 🟢 STATIS | Hardcoded (left=0.76, right=4.19) | Section break terpisah |

> [!NOTE]
> **Lampiran muncul HANYA JIKA** user mengupload foto kegiatan. Jika tidak ada foto, lampiran tidak di-generate.

---

## Logo yang Otomatis Terisi (Hardcoded SMKN4)

| Logo | File | Posisi | Ukuran |
|------|------|--------|--------|
| Logo SMKN4 (bola dunia) | `smkn4_assets/image1.jpeg` | Cover: antara nama siswa dan NIS, center | ~6.16cm × 4.87cm |
| Logo Provinsi Lampung | `smkn4_assets/image2.png` | Cover: samping kiri teks "PEMERINTAH PROVINSI LAMPUNG", **anchor** | ~2.70cm × 3.88cm |
| Logo SMKN4 (repeat) | `smkn4_assets/image1.jpeg` | Cover Dalam: posisi identik | Sama |
| Logo Provinsi (repeat) | `smkn4_assets/image2.png` | Cover Dalam: posisi identik | Sama |

> [!NOTE]
> Di dokumen Niken, logo Provinsi Lampung muncul **sebagai anchor image** (floating) di samping kiri teks kop sekolah, BUKAN inline. Ini penting untuk layout yang benar.

---

## Ringkasan: Apa yang User Perlu Input

### 🔵 DATA WAJIB (harus diisi user)

| Kategori | Field |
|----------|-------|
| **Siswa** | Nama, NISN, Tempat Lahir, Tanggal Lahir, Jenis Kelamin, No HP, Nama Ortu, Alamat Ortu, No HP Ortu, Jurusan, Pas Foto 3×4 |
| **Perusahaan** | Nama, Alamat, Bidang Usaha, No Telp, Nama Pimpinan, Jabatan Pimpinan, Nama Pembimbing Industri, Jabatan Pembimbing |
| **Sekolah** | Nama Ketua KK + NIP, Nama Pembimbing Sekolah + NIP, Nama Waka Humas + NIP |
| **Durasi** | Tanggal mulai PKL, Tanggal selesai PKL |
| **Cerita** | Cerita pengalaman PKL (min ~300 kata) |
| **Tanggal Laporan** | Tanggal penulisan laporan (untuk Kata Pengantar) |

### 🟡 DATA OPSIONAL (boleh diisi, boleh tidak)

| Kategori | Field | Efek jika ada |
|----------|-------|---------------|
| **Siswa** | Golongan Darah, Catatan Kesehatan | Isi tabel identitas |
| **Perusahaan** | Fax, Email, Website, Status (PMDN/PMA), HRD (nama/telp/email) | Isi tabel identitas industri |
| **Profil Perusahaan** | Sejarah, Visi, Misi, Tata Tertib, Jadwal Kerja, Job Description, Bagan Struktur (gambar) | Menambah sub-bab di BAB I |
| **Peralatan** | Daftar nama peralatan + foto | Menambah sub-bab di BAB IV |
| **Lampiran** | Foto-foto kegiatan + caption | Section LAMPIRAN muncul |

### 🟢 DATA OTOMATIS (bawaan sistem, tidak perlu input)

- Seluruh BAB III (Landasan Teori, Asas PKL, Sejarah SMKN4)
- Kop sekolah + logo SMKN4 + logo Provinsi Lampung
- Template Kata Pengantar
- Template tujuan PKL (9 poin)
- Format, margin, font, spacing, page numbering
- Daftar Isi (auto-generate)
- Referensi default (UU, PP, website sekolah)

### 🤖 DATA AI-GENERATED (dari cerita pengalaman)

- BAB I: Sejarah perusahaan, visi-misi, tata tertib, job description (jika user tidak input manual)
- BAB II: Ringkasan poin kegiatan per divisi
- BAB IV: Elaborasi detail kegiatan + peralatan
- BAB V: Refleksi/pembahasan
- BAB VI: Kesimpulan + saran
- Daftar Pustaka tambahan

---

## Open Questions

> [!IMPORTANT]
> **Q1: Sub-bab BAB I dari cerita atau input manual?**
> Sejarah perusahaan, visi-misi, tata tertib, jadwal kerja, job description — apakah ini semua diekstrak AI dari cerita user, atau user harus input manual di form terpisah? 
> 
> Rekomendasi: **Campuran** — AI coba ekstrak dari cerita, lalu user bisa review & edit di step ReviewAI.

> [!IMPORTANT]  
> **Q2: Bagan struktur organisasi — bagaimana?**
> Di Niken ada gambar bagan (image7, 17.97cm × 14.45cm). Apakah user harus upload gambar bagan sendiri, atau kita generate ASCII/teks bagan dari job description?
>
> Rekomendasi: **Upload gambar** — karena bagan setiap perusahaan terlalu unik untuk di-auto-generate.

> [!IMPORTANT]
> **Q3: Tabel perhitungan di BAB IV — general atau jurusan-specific?**
> Niken (Akuntansi) punya tabel perhitungan keuangan. Siswa RPL mungkin punya tabel konfigurasi server. Apakah kita support tabel dinamis di BAB IV?
>
> Rekomendasi: **Skip untuk V1** — fokus ke teks elaborasi dulu. Tabel bisa ditambahkan user manual di Word.
