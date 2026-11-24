import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/barcode.dart';

/// Écran plein cadre de lecture de code-barres. Renvoie le code lu (ou saisi), ou null.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    // Uniquement les codes des produits : plus rapide et évite de lire un QR code voisin.
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
  );
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && isPlausibleCode(raw)) {
        _done = true;
        Navigator.of(context).pop(normalizeCode(raw));
        return;
      }
    }
  }

  Future<void> _typeCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(builder: (ctx, setLocal) {
          void submit() {
            if (isPlausibleCode(controller.text)) {
              Navigator.pop(ctx, normalizeCode(controller.text));
            } else {
              setLocal(() => error = 'Code invalide (8, 10, 12 ou 13 chiffres)');
            }
          }

          return AlertDialog(
            title: const Text('Saisir le code'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'ISBN ou code EAN', errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(onPressed: submit, child: const Text('Rechercher')),
            ],
          );
        });
      },
    );
    if (code != null && mounted && !_done) {
      _done = true;
      Navigator.of(context).pop(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scanner'),
        actions: [
          IconButton(
            tooltip: _torch ? 'Éteindre la lampe' : 'Allumer la lampe',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final window = Rect.fromCenter(
          center: size.center(const Offset(0, -40)),
          width: size.width * 0.8,
          height: size.width * 0.45,
        );
        return Stack(fit: StackFit.expand, children: [
          MobileScanner(
            controller: _controller,
            scanWindow: window,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ErrorView(
              message: error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'L\'accès à l\'appareil photo a été refusé. Autorisez-le dans les réglages '
                      'Android de l\'application, ou saisissez le code à la main.'
                  : 'Impossible de démarrer l\'appareil photo.',
            ),
          ),
          CustomPaint(painter: _WindowPainter(window)),
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 24,
            child: const Text(
              'Visez le code-barres au dos du livre, de la BD ou de la pochette',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: SafeArea(
              child: Center(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Saisir le code à la main'),
                  onPressed: _typeCode,
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Assombrit l'image autour de la zone de lecture.
class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(16));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}
