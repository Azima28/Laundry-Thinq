# Bardi / Tuya Smart Device Controller Module

This module provides a standalone command-line integration to synchronize, monitor, and control Bardi smart plugs and sensors using the Tuya Cloud API.

---

## 1. Directory Structure

This folder contains the following files:

* **`sync_keys.py`**: Queries the Tuya Cloud API to download the list of all registered devices (and their static `local_key` values) and saves them locally into `devices.json`.
* **`control_plug.py`**: Reads `devices.json`, prompts the user to select which device they want to control, starts a background polling thread for real-time state tracking, and processes user input commands (`on`, `off`, `exit`).
* **`devices.json`**: (Generated dynamically by `sync_keys.py`) Stores your Tuya developer credentials and linked device list.

---

## 2. Active Credentials Reference

For manual integration or debugging, these are the credentials currently active:

* **Access ID / Client ID**: `gst7mf5yytp73c9cvqjq`
* **Access Secret / Client Secret**: `3d909f01f5ad4d96aae95a7b454d8957`
* **App Account UID**: `az1733062861059ZHSHA`
* **Data Center / Region**: `Western America Data Center` (`us` endpoint)

---

## 3. How to Setup and Run

### Step 1: Install Dependencies
Make sure the `tinytuya` python package is installed in your python environment:
```bash
pip install tinytuya
```

### Step 2: Synchronize Devices
Fetch the latest list of devices and their keys from the cloud:
```bash
python sync_keys.py
```
This will generate the `devices.json` configuration file, listing your active devices (such as "Pengering 4" and the "Gas sensors").

### Step 3: Launch Interactive Control
Run the control loop program:
```bash
python control_plug.py
```
* The script will list all available devices in your account.
* Enter the number of the device you want to control (e.g. `1` for `Pengering 4`).
* Type `on` and press **Enter** to turn it ON.
* Type `off` and press **Enter** to turn it OFF.
* Type `exit` and press **Enter** to quit.

---

## 4. Notes for Future Agents

* **Device Retrieval Logic (Cara Kerja Pengambilan Perangkat)**:
  * **Perbedaan UID**: Jangan gunakan token `uid` developer (Developer UID) dari `/v1.0/token` untuk menarik perangkat, karena hasilnya akan kosong `[]`. Perangkat dipasangkan ke aplikasi HP, sehingga sistem **harus** mengueri list menggunakan UID Akun HP (App UID): **`az1733062861059ZHSHA`** ke endpoint `/v1.0/users/{APP_UID}/devices`.
  * **Regional Server Lock**: Project ini terdaftar di server Western America, sehingga API wajib menembak host **`https://openapi.tuyaus.com`** (atau parameter `apiRegion="us"` di Python). Menembak wilayah lain akan mengakibatkan error `clientId is invalid`.
* **Real-time Monitoring**: `control_plug.py` implements a background thread that polls `/v1.0/devices/{id}` every 2 seconds. When it detects a state change, it logs the change to the console without interrupting user inputs.
* **Adding New Devices**: To add a new smartplug or sensor, simply pair it using the **Smart Life** app on your phone, then run `python sync_keys.py` again.
* **Integrating with Laundry Frontend**:
  * The Flask server in the `laundry` backend ([main.py](file:///c:/Work/project%20laundry/laundry/main.py)) implements a bridge route `/api/tuya/sync-keys` that uses the same credentials.
  * Flutter screen files can send HTTP requests to the Flask server to retrieve these dynamic keys or state logs.
