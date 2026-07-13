package com.example.flutter_application_1

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.Executors
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.azima/printer"
	private val REQUEST_PRINT_PERMS = 1001
	private val REQUEST_SCAN_PERMS = 1002
	private var pendingPrintArgs: Map<*, *>? = null
	private var pendingPrintResult: MethodChannel.Result? = null
	private var pendingMethod: String? = null
	private var pendingScanResult: MethodChannel.Result? = null
	private val printExecutor = Executors.newSingleThreadExecutor()

	// Discovery state
	private val discoveredDevices = ArrayList<Map<String, String>>()
	private var discoveryReceiver: BroadcastReceiver? = null
	private var methodChannel: MethodChannel? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
		methodChannel = channel

		channel.setMethodCallHandler { call, result ->
			when (call.method) {
				"openBluetoothSettings" -> {
					val intent = Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
					startActivity(intent)
					result.success(true)
				}
				"getBondedDevices" -> handleGetBondedDevices(result)
				"checkDeviceReachable" -> {
					val address = call.argument<String>("address")
					handleCheckReachable(address, result)
				}
				"startDiscovery" -> handleStartDiscovery(result)
				"stopDiscovery" -> handleStopDiscovery(result)
				"pairDevice" -> {
					val address = call.argument<String>("address")
					handlePairDevice(address, result)
				}
				"unpairDevice" -> {
					val address = call.argument<String>("address")
					handleUnpairDevice(address, result)
				}
				"isBluetoothEnabled" -> {
					val adapter = BluetoothAdapter.getDefaultAdapter()
					result.success(adapter?.isEnabled == true)
				}
				"enableBluetooth" -> {
					val adapter = BluetoothAdapter.getDefaultAdapter()
					if (adapter == null) {
						result.error("NO_BT", "No Bluetooth adapter", null)
					} else if (!adapter.isEnabled) {
						val enableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
						startActivityForResult(enableIntent, 1003)
						result.success(true)
					} else {
						result.success(true)
					}
				}
				"printTest" -> {
					val args = call.arguments as? Map<*, *>
					val address = args?.get("address") as? String
					if (address.isNullOrBlank()) {
						result.error("NO_ADDRESS", "No Bluetooth address provided", null)
						return@setMethodCallHandler
					}
					if (!hasPrintPermissions()) {
						pendingPrintArgs = args
						pendingPrintResult = result
						pendingMethod = "printTest"
						requestPrintPermissions()
						return@setMethodCallHandler
					}
					printExecutor.submit {
						val ok = performPrintSync(args)
						Log.i("MainActivity", "printTest completed (ok=$ok)")
					}
					result.success(true)
				}
				"printOrder" -> {
					val args = call.arguments as? Map<*, *>
					val address = args?.get("address") as? String
					if (address.isNullOrBlank()) {
						result.error("NO_ADDRESS", "No Bluetooth address provided", null)
						return@setMethodCallHandler
					}
					if (!hasPrintPermissions()) {
						pendingPrintArgs = args
						pendingPrintResult = result
						pendingMethod = "printOrder"
						requestPrintPermissions()
						return@setMethodCallHandler
					}
					printExecutor.submit {
						val ok = performPrintOrderSync(args)
						Log.i("MainActivity", "printOrder completed (ok=$ok)")
					}
					result.success(true)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun requestPrintPermissions() {
		val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
		} else {
			arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
		}
		ActivityCompat.requestPermissions(this, perms, REQUEST_PRINT_PERMS)
	}

	private fun hasScanPermissions(): Boolean {
		return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
			ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
		} else {
			ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
		}
	}

	// ── getBondedDevices ──
	private fun handleGetBondedDevices(result: MethodChannel.Result) {
		try {
			val adapter = BluetoothAdapter.getDefaultAdapter()
			if (adapter == null) { result.error("NO_BT", "No Bluetooth adapter", null); return }
			val list = ArrayList<Map<String, String>>()
			for (device in adapter.bondedDevices ?: emptySet()) {
				val map = HashMap<String, String>()
				map["name"] = device.name ?: "Unknown"
				map["address"] = device.address
				map["type"] = when (device.bluetoothClass?.majorDeviceClass) {
					0x0600 -> "imaging" // printers, scanners
					else -> "other"
				}
				list.add(map)
			}
			result.success(list)
		} catch (e: SecurityException) {
			result.error("PERMISSION", "Bluetooth permission denied", null)
		} catch (e: Exception) {
			result.error("ERROR", e.message, null)
		}
	}

	// ── checkDeviceReachable: quick RFCOMM ping ──
	private fun handleCheckReachable(address: String?, result: MethodChannel.Result) {
		if (address.isNullOrBlank()) { result.success(false); return }
		printExecutor.submit {
			var reachable = false
			var socket: BluetoothSocket? = null
			try {
				val adapter = BluetoothAdapter.getDefaultAdapter() ?: return@submit
				val device = adapter.getRemoteDevice(address)
				val uuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
				socket = device.createRfcommSocketToServiceRecord(uuid)
				adapter.cancelDiscovery()
				socket.connect() // will throw if not reachable
				reachable = true
			} catch (_: Exception) {
				reachable = false
			} finally {
				try { socket?.close() } catch (_: Exception) {}
			}
			runOnUiThread { result.success(reachable) }
		}
	}

	// ── startDiscovery ──
	private fun handleStartDiscovery(result: MethodChannel.Result) {
		if (!hasScanPermissions()) {
			pendingScanResult = result
			val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
				arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.ACCESS_FINE_LOCATION)
			} else {
				arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
			}
			ActivityCompat.requestPermissions(this, perms, REQUEST_SCAN_PERMS)
			return
		}
		doStartDiscovery(result)
	}

	private fun doStartDiscovery(result: MethodChannel.Result) {
		try {
			val adapter = BluetoothAdapter.getDefaultAdapter()
			if (adapter == null) { result.error("NO_BT", "No Bluetooth adapter", null); return }
			if (!adapter.isEnabled) { result.error("BT_OFF", "Bluetooth is not enabled", null); return }

			discoveredDevices.clear()
			// Unregister old receiver if any
			unregisterDiscoveryReceiver()

			discoveryReceiver = object : BroadcastReceiver() {
				override fun onReceive(context: Context?, intent: Intent?) {
					when (intent?.action) {
						BluetoothDevice.ACTION_FOUND -> {
							val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
							if (device != null) {
								val name = try { device.name } catch (_: SecurityException) { null }
								val addr = device.address
								// Avoid duplicates
								if (discoveredDevices.none { it["address"] == addr }) {
									val map = HashMap<String, String>()
									map["name"] = name ?: "Unknown"
									map["address"] = addr
									map["bonded"] = if (device.bondState == BluetoothDevice.BOND_BONDED) "true" else "false"
									discoveredDevices.add(map)
									// Notify Flutter
									methodChannel?.invokeMethod("onDeviceFound", map)
								}
							}
						}
						BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
							methodChannel?.invokeMethod("onDiscoveryFinished", null)
						}
					}
				}
			}

			val filter = IntentFilter().apply {
				addAction(BluetoothDevice.ACTION_FOUND)
				addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
			}
			registerReceiver(discoveryReceiver, filter)

			if (adapter.isDiscovering) adapter.cancelDiscovery()
			adapter.startDiscovery()
			result.success(true)
		} catch (e: SecurityException) {
			result.error("PERMISSION", "Permission denied for discovery", null)
		} catch (e: Exception) {
			result.error("ERROR", e.message, null)
		}
	}

	private fun handleStopDiscovery(result: MethodChannel.Result) {
		try {
			val adapter = BluetoothAdapter.getDefaultAdapter()
			adapter?.cancelDiscovery()
			unregisterDiscoveryReceiver()
			result.success(true)
		} catch (e: Exception) {
			result.success(true) // best-effort
		}
	}

	private fun unregisterDiscoveryReceiver() {
		if (discoveryReceiver != null) {
			try { unregisterReceiver(discoveryReceiver) } catch (_: Exception) {}
			discoveryReceiver = null
		}
	}

	// ── pairDevice ──
	private fun handlePairDevice(address: String?, result: MethodChannel.Result) {
		if (address.isNullOrBlank()) { result.error("NO_ADDRESS", "Address required", null); return }
		try {
			val adapter = BluetoothAdapter.getDefaultAdapter() ?: run { result.error("NO_BT", "No adapter", null); return }
			adapter.cancelDiscovery()
			val device = adapter.getRemoteDevice(address)
			if (device.bondState == BluetoothDevice.BOND_BONDED) {
				result.success(true)
				return
			}
			// createBond triggers the system pairing dialog (PIN entry etc.)
			val success = device.createBond()
			// Register receiver to listen for bond state change
			val bondReceiver = object : BroadcastReceiver() {
				override fun onReceive(context: Context?, intent: Intent?) {
					val bondDevice: BluetoothDevice? = intent?.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
					if (bondDevice?.address == address) {
						when (bondDevice?.bondState) {
							BluetoothDevice.BOND_BONDED -> {
								try { unregisterReceiver(this) } catch (_: Exception) {}
								methodChannel?.invokeMethod("onPairResult", mapOf("address" to address, "success" to true))
							}
							BluetoothDevice.BOND_NONE -> {
								try { unregisterReceiver(this) } catch (_: Exception) {}
								methodChannel?.invokeMethod("onPairResult", mapOf("address" to address, "success" to false))
							}
						}
					}
				}
			}
			registerReceiver(bondReceiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
			result.success(success)
		} catch (e: SecurityException) {
			result.error("PERMISSION", "Permission denied", null)
		} catch (e: Exception) {
			result.error("ERROR", e.message, null)
		}
	}

	private fun handleUnpairDevice(address: String?, result: MethodChannel.Result) {
		if (address.isNullOrBlank()) { result.error("NO_ADDRESS", "Address required", null); return }
		try {
			val adapter = BluetoothAdapter.getDefaultAdapter() ?: run { result.error("NO_BT", "No adapter", null); return }
			val device = adapter.getRemoteDevice(address)
			val method = device.javaClass.getMethod("removeBond")
			method.invoke(device)
			result.success(true)
		} catch (e: Exception) {
			result.error("ERROR", e.message, null)
		}
	}

	private fun hasPrintPermissions(): Boolean {
		return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
					ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
		} else {
			ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
		}
	}

	private fun performPrintSync(args: Map<*, *>?): Boolean {
		val address = args?.get("address") as? String ?: return false
		val businessName = (args?.get("businessName") as? String) ?: "Laundry App"
		val businessAddress = (args?.get("businessAddress") as? String) ?: ""
		val businessPhone = (args?.get("businessPhone") as? String) ?: ""

		val maxAttempts = 2
		for (attempt in 1..maxAttempts) {
			var socket: BluetoothSocket? = null
			var out: java.io.OutputStream? = null
			try {
				val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() ?: return false
				val device = bluetoothAdapter.getRemoteDevice(address)
				val uuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
				socket = try { device.createRfcommSocketToServiceRecord(uuid) } catch (e: Exception) {
					try { val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType); m.invoke(device, 1) as? BluetoothSocket } catch (ex: Exception) { null }
				}
				bluetoothAdapter.cancelDiscovery()
				Thread.sleep(120)
				socket?.connect()
				out = socket?.outputStream
				val bos = ByteArrayOutputStream()
				bos.write(byteArrayOf(0x1B, 0x40))
				bos.write(byteArrayOf(0x1B, 0x61, 0x01))
				bos.write((businessName + "\n").toByteArray())
				if (businessAddress.isNotBlank()) bos.write((businessAddress + "\n").toByteArray())
				if (businessPhone.isNotBlank()) bos.write(("Tel: " + businessPhone + "\n").toByteArray())
				bos.write(byteArrayOf(0x1B, 0x61, 0x00))
				bos.write("------------------------------\n".toByteArray())
				bos.write("Sample Receipt\n".toByteArray())
				bos.write("Item 1    1 x 10.00\n".toByteArray())
				bos.write("Total     10.00\n".toByteArray())
				bos.write("\n\n\n".toByteArray())
				bos.write(byteArrayOf(0x1D, 0x56, 0x00))
				out?.write(bos.toByteArray())
				out?.flush()
				Thread.sleep(150)
				return true
			} catch (e: Exception) {
				Log.e("MainActivity", "Error printing attempt $attempt", e)
				if (attempt < maxAttempts) { try { Thread.sleep(200) } catch (_: InterruptedException) {} }
			} finally {
				try { out?.close() } catch (_: Exception) {}
				try { socket?.close() } catch (_: Exception) {}
				try { Thread.sleep(80) } catch (_: InterruptedException) {}
			}
		}
		return false
	}

	private fun performPrintOrderSync(args: Map<*, *>?): Boolean {
		val orderMap = args?.get("order") as? Map<*, *> ?: return false
		val businessName = (args?.get("businessName") as? String) ?: "Laundry App"
		val businessAddress = (args?.get("businessAddress") as? String) ?: ""
		val businessPhone = (args?.get("businessPhone") as? String) ?: ""
		val address = (args["address"] as? String) ?: return false

		val bosAll = ByteArrayOutputStream()
		try {
			bosAll.write(byteArrayOf(0x1B, 0x40))
			bosAll.write(byteArrayOf(0x1B, 0x61, 0x01))
			bosAll.write((businessName + "\n").toByteArray())
			if (businessAddress.isNotBlank()) bosAll.write((businessAddress + "\n").toByteArray())
			if (businessPhone.isNotBlank()) bosAll.write(("Tel: " + businessPhone + "\n").toByteArray())
			bosAll.write(byteArrayOf(0x1B, 0x61, 0x00))
			bosAll.write("--------------------------------\n".toByteArray())
			val orderId = orderMap["id"]?.toString() ?: ""
			val customer = orderMap["customerName"]?.toString() ?: ""
			val orderDateRaw = orderMap["orderDate"]?.toString() ?: ""
			val paymentMethod = orderMap["paymentMethod"]?.toString() ?: ""
			var dateStr = orderDateRaw
			var timeStr = ""
			try {
				val odt = java.time.OffsetDateTime.parse(orderDateRaw)
				dateStr = odt.toLocalDate().format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd"))
				timeStr = odt.toLocalTime().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm"))
			} catch (e: Exception) {
				try {
					val ldt = java.time.LocalDateTime.parse(orderDateRaw)
					dateStr = ldt.toLocalDate().format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd"))
					timeStr = ldt.toLocalTime().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm"))
				} catch (e2: Exception) {
					if (orderDateRaw.contains("T")) {
						val parts = orderDateRaw.split("T")
						if (parts.isNotEmpty()) dateStr = parts[0]
						if (parts.size > 1) {
							val m = Regex("^(\\d{2}:\\d{2})").find(parts[1])
							if (m != null) timeStr = m.groupValues[1]
						}
					}
				}
			}
			bosAll.write(("Order: #$orderId\n").toByteArray())
			bosAll.write(("Nama: $customer\n").toByteArray())
			bosAll.write(("Tanggal: $dateStr ${if (timeStr.isNotEmpty()) timeStr else ""}\n").toByteArray())
			bosAll.write(("Metode: $paymentMethod\n").toByteArray())
			bosAll.write("--------------------------------\n".toByteArray())
			@Suppress("UNCHECKED_CAST")
			val items = orderMap["items"] as? List<Map<*, *>> ?: emptyList()
			for (it in items) {
				val name = it["itemName"]?.toString() ?: ""
				val qty = (it["quantity"] as? Number)?.toInt() ?: 0
				val price = (it["price"] as? Number)?.toInt() ?: 0
				bosAll.write(String.format("%-16s %3d x %7d\n", name.take(16), qty, price).toByteArray())
				if (it["note"] != null) bosAll.write(("  * ${it["note"]}\n").toByteArray())
			}
			bosAll.write("--------------------------------\n".toByteArray())
			bosAll.write(("Total: Rp${orderMap["totalAmount"]?.toString() ?: "0"}\n").toByteArray())
			bosAll.write("\n\n\n".toByteArray())
			bosAll.write(byteArrayOf(0x1D, 0x56, 0x00))
		} catch (e: Exception) { return false }

		val maxAttempts = 2
		for (attempt in 1..maxAttempts) {
			var socket: BluetoothSocket? = null
			var out: java.io.OutputStream? = null
			try {
				val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() ?: return false
				val device = bluetoothAdapter.getRemoteDevice(address)
				val uuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
				socket = try { device.createRfcommSocketToServiceRecord(uuid) } catch (e: Exception) {
					try { val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType); m.invoke(device, 1) as? BluetoothSocket } catch (ex: Exception) { null }
				}
				bluetoothAdapter.cancelDiscovery()
				Thread.sleep(120)
				socket?.connect()
				out = socket?.outputStream
				out?.write(bosAll.toByteArray())
				out?.flush()
				Thread.sleep(150)
				return true
			} catch (e: Exception) {
				Log.e("MainActivity", "Error printing order attempt $attempt", e)
				if (attempt < maxAttempts) { try { Thread.sleep(200) } catch (_: InterruptedException) {} }
			} finally {
				try { out?.close() } catch (_: Exception) {}
				try { socket?.close() } catch (_: Exception) {}
				try { Thread.sleep(80) } catch (_: InterruptedException) {}
			}
		}
		return false
	}

	override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }

		when (requestCode) {
			REQUEST_PRINT_PERMS -> {
				if (granted && pendingPrintArgs != null && pendingPrintResult != null) {
					if (pendingMethod == "printTest") {
						printExecutor.submit { performPrintSync(pendingPrintArgs) }
						pendingPrintResult?.success(true)
					} else if (pendingMethod == "printOrder") {
						printExecutor.submit { performPrintOrderSync(pendingPrintArgs) }
						pendingPrintResult?.success(true)
					} else {
						pendingPrintResult?.success(true)
					}
				} else {
					pendingPrintResult?.error("PERMISSION", "Required permissions not granted", null)
				}
				pendingPrintArgs = null
				pendingPrintResult = null
			}
			REQUEST_SCAN_PERMS -> {
				if (granted && pendingScanResult != null) {
					doStartDiscovery(pendingScanResult!!)
				} else {
					pendingScanResult?.error("PERMISSION", "Scan permissions not granted", null)
				}
				pendingScanResult = null
			}
		}
	}

	override fun onDestroy() {
		unregisterDiscoveryReceiver()
		super.onDestroy()
	}
}
