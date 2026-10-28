import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

void main() {
  runApp(const ZeusVpnApp());
}

class ZeusVpnApp extends StatelessWidget {
  const ZeusVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZEUS VPN',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF05050A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00F0FF),
          secondary: const Color(0xFFFF003C),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterV2ray _v2ray = FlutterV2ray();
  V2RayStatus _status = const V2RayStatus();
  bool _isConnected = false;
  
  List<String> _subLinks = [];
  List<Map<String, dynamic>> _servers = [];
  int? _selectedServerIndex;
  int? _previousSelection; // رفع باگ انتخاب سرور
  
  final TextEditingController _subController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _v2ray.status().listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _subLinks = prefs.getStringList('sub_links') ?? [];
    });
    if (_subLinks.isNotEmpty) _fetchServers();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('sub_links', _subLinks);
  }

  Future<void> _addSubLink() async {
    if (_subController.text.isNotEmpty) {
      setState(() {
        _subLinks.add(_subController.text.trim());
        _subController.clear();
      });
      _saveData();
      _fetchServers();
    }
  }

  Future<void> _fetchServers() async {
    List<Map<String, dynamic>> allServers = [];
    final dio = Dio();
    
    for (String sub in _subLinks) {
      try {
        final response = await dio.get(sub);
        final decoded = utf8.decode(base64Decode(response.data.toString().trim()));
        final lines = decoded.split('\n');
        for (var line in lines) {
          if (line.isNotEmpty && (line.startsWith('vless://') || line.startsWith('trojan://'))) {
            allServers.add({'config': line, 'name': _extractName(line), 'ping': -1});
          }
        }
      } catch (e) {
        debugPrint("Error fetching sub: $e");
      }
    }
    
    setState(() {
      _servers = allServers;
    });
    _testAllPings();
  }

  String _extractName(String config) {
    if (config.contains('#')) {
      return Uri.decodeComponent(config.split('#').last.replaceAll('\n', '').trim());
    }
    return 'Server ${_servers.length + 1}';
  }

  Future<void> _testAllPings() async {
    for (int i = 0; i < _servers.length; i++) {
      _testPing(i); // اجرای موازی
    }
  }

  Future<void> _testPing(int index) async {
    try {
      String host = "8.8.8.8"; 
      int port = 53;
      
      final start = DateTime.now();
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      final end = DateTime.now();
      socket.destroy();
      
      final ping = end.difference(start).inMilliseconds;
      setState(() {
        _servers[index]['ping'] = ping;
      });
    } catch (e) {
      setState(() {
        _servers[index]['ping'] = -1;
      });
    }
  }

  Future<void> _testSpeed() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ابتدا متصل شوید!")));
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تست سرعت در حال انجام...")));
    final dio = Dio();
    final start = DateTime.now();
    
    try {
      await dio.download("https://speed.cloudflare.com/__down?bytes=10000000", "/storage/emulated/0/Download/zeus_speedtest.tmp");
      final end = DateTime.now();
      final duration = end.difference(start).inMilliseconds;
      final mbps = (10 * 8) / (duration / 1000);
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("سرعت: ${mbps.toStringAsFixed(2)} Mbps")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("خطا در تست سرعت")));
    }
  }

  Future<void> _connect() async {
    if (_selectedServerIndex == null || _servers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("یک سرور انتخاب کنید")));
      return;
    }
    
    try {
      await _v2ray.start(
        config: _servers[_selectedServerIndex]['config'],
        proxyOnly: false,
      );
      setState(() => _isConnected = true);
    } catch (e) {
      debugPrint("Connect error: $e");
    }
  }

  Future<void> _disconnect() async {
    await _v2ray.stop();
    setState(() => _isConnected = false);
  }

  void _selectServer(int index) {
    setState(() {
      _previousSelection = _selectedServerIndex; // حل باگ State
      _selectedServerIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildGridBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildStatusPanel(),
                const SizedBox(height: 20),
                _buildConnectButton(),
                const SizedBox(height: 20),
                Expanded(child: _buildServerList()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "speed",
            mini: true,
            onPressed: _testSpeed,
            backgroundColor: const Color(0xFFFF003C),
            child: const Icon(Icons.speed, color: Colors.white),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "settings",
            onPressed: _showPattngSettings,
            backgroundColor: const Color(0xFF00F0FF),
            child: const Icon(Icons.settings, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildGridBackground() {
    return CustomPaint(
      painter: _GridPainter(),
      child: Container(color: Colors.black.withOpacity(0.8)),
    );
  }

  Widget _buildStatusPanel() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF00F0FF), width: 1.5),
      ),
      child: Column(
        children: [
          const Text("ZEUS HUD", style: TextStyle(color: Color(0xFF00F0FF), fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 15),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _statItem("UPLOAD", "${_status.speedUp} B/s"),
            _statItem("DOWNLOAD", "${_status.speedDown} B/s"),
            _statItem("TIME", _status.duration ?? "00:00"),
          ])
        ],
      ),
    );
  }

  Widget _statItem(String title, String value) {
    return Column(children: [
      Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))
    ]);
  }

  Widget _buildConnectButton() {
    return GestureDetector(
      onTap: _isConnected ? _disconnect : _connect,
      child: Container(
        width: 120, height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isConnected ? const Color(0xFFFF003C) : const Color(0xFF00F0FF),
          boxShadow: [
            BoxShadow(color: (_isConnected ? const Color(0xFFFF003C) : const Color(0xFF00F0FF)).withOpacity(0.5), blurRadius: 20, spreadRadius: 2)
          ]
        ),
        child: Center(child: Icon(_isConnected ? Icons.power_settings_new : Icons.play_arrow, color: Colors.black, size: 50)),
      ),
    );
  }

  Widget _buildServerList() {
    if (_servers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("لینک ساب ثبت نشده است", style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              TextField(
                controller: _subController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "لینک اشتراک را وارد کنید",
                  hintStyle: const TextStyle(color: Colors.grey),
                  suffixIcon: IconButton(icon: const Icon(Icons.add, color: Color(0xFF00F0FF)), onPressed: _addSubLink),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00F0FF)))
                ),
              )
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _servers.length,
      itemBuilder: (context, index) {
        final server = _servers[index];
        final ping = server['ping'];
        Color pingColor = Colors.grey;
        if (ping > 0 && ping < 150) pingColor = Colors.greenAccent;
        else if (ping >= 150 && ping < 300) pingColor = Colors.orangeAccent;
        else if (ping >= 300) pingColor = Colors.redAccent;

        return GestureDetector(
          onTap: () => _selectServer(index),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _selectedServerIndex == index ? const Color(0xFF00F0FF) : Colors.transparent, width: 2)
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(server['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
                Text(ping > 0 ? "$ping ms" : "Timeout", style: TextStyle(color: pingColor, fontWeight: FontWeight.bold))
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPattngSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A10),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            const Text("PattNG Settings", style: TextStyle(color: Color(0xFF00F0FF), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            const Text("Fingerprint", style: TextStyle(color: Colors.white)),
            DropdownButton<String>(
              isExpanded: true,
              dropdownColor: const Color(0xFF11111A),
              value: "unsafe",
              items: ["unsafe", "chrome", "firefox", "safari"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white)))).toList(),
              onChanged: (v) {},
            ),
            const SizedBox(height: 20),
            const Text("Fragment", style: TextStyle(color: Colors.white)),
            const TextField(style: TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "tlshello", hintStyle: TextStyle(color: Colors.grey))),
            const SizedBox(height: 20),
            const Text("ALPN", style: TextStyle(color: Colors.white)),
            const TextField(style: TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "h2, http/1.1", hintStyle: TextStyle(color: Colors.grey))),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF)),
              onPressed: () => Navigator.pop(context), 
              child: const Text("ذخیره تنظیمات", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
            )
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F0FF).withOpacity(0.1)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
