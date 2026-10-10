/// The touch player's subtitle size control.
///
/// A drag previews the number locally. Persistence happens once on release,
/// rather than issuing a storage write for every pixel the thumb travels.
library;

import 'package:flutter/material.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../widgets/hotstar_player_style.dart';
import 'player_panel_metrics.dart';

class PlayerSubtitleSizeSlider extends StatefulWidget {
  const PlayerSubtitleSizeSlider({
    required this.value,
    required this.onChangeEnd,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChangeEnd;

  @override
  State<PlayerSubtitleSizeSlider> createState() =>
      _PlayerSubtitleSizeSliderState();
}

class _PlayerSubtitleSizeSliderState extends State<PlayerSubtitleSizeSlider> {
  double? _preview;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant PlayerSubtitleSizeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once the persisted value arrives, it owns the thumb again. While a
    // finger is dragging, a settings refresh must not snap the thumb back.
    if (!_dragging && oldWidget.value != widget.value) _preview = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final metrics = PlayerPanelMetrics.of(context);
    final size = (_preview ?? widget.value).clamp(10.0, 80.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.textSize,
                style: TextStyle(
                  color: HotstarPlayerStyle.primaryText,
                  fontSize: metrics.rowLabelSize,
                ),
              ),
              Text(
                '${size.round()}',
                style: TextStyle(
                  color: metrics.secondaryText,
                  fontSize: metrics.rowDetailSize,
                ),
              ),
            ],
          ),
          Slider(
            value: size,
            min: 10,
            max: 80,
            divisions: 70,
            label: '${size.round()}',
            activeColor: HotstarPlayerStyle.accent,
            semanticFormatterCallback: (value) => '${value.round()}',
            onChanged: (value) => setState(() {
              _dragging = true;
              _preview = value;
            }),
            onChangeEnd: (value) {
              setState(() => _dragging = false);
              widget.onChangeEnd(value.roundToDouble());
            },
          ),
        ],
      ),
    );
  }
}
