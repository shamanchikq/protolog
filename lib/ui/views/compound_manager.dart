import 'package:flutter/material.dart';
import '../../models.dart';
import '../../utils.dart';

class CompoundManager extends StatefulWidget {
  final List<CompoundDefinition> userCompounds;
  final Function(CompoundDefinition) onAdd;
  final Function(String) onDelete;
  final VoidCallback onExport;
  final VoidCallback onImport;

  const CompoundManager({super.key, required this.userCompounds, required this.onAdd, required this.onDelete, required this.onExport, required this.onImport});

  @override
  State<CompoundManager> createState() => _CompoundManagerState();
}

class _CompoundManagerState extends State<CompoundManager> {
  bool isCreating = false;
  String base = '';
  String ester = '';
  CompoundType type = CompoundType.steroid;
  GraphType graphType = GraphType.curve;
  String halfLife = '2';
  String timeToPeak = '1';
  String ratio = '100';
  Unit unit = Unit.mg;

  void _save() {
    final comp = CompoundDefinition(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      base: base,
      ester: ester.isEmpty ? 'None' : ester,
      type: type,
      // Removed Curve option for Peptides/Ancillaries per request
      graphType: (type == CompoundType.steroid || type == CompoundType.oral) ? GraphType.curve : graphType,
      halfLife: double.tryParse(halfLife) ?? 0,
      timeToPeak: double.tryParse(timeToPeak) ?? 0,
      ratio: (double.tryParse(ratio) ?? 100) / 100,
      unit: unit,
      colorValue: type == CompoundType.steroid ? 0xFF10B981 : 0xFF8B5CF6,
      isCustom: true,
    );
    widget.onAdd(comp);
    setState(() => isCreating = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isCreating) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => isCreating = false)), const Text("Create Compound", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 16),
            _buildField("Base Name", (v) => base = v),
            const SizedBox(height: 12),
            _buildDropdown("Type", type, CompoundType.values, (v) => setState(() => type = v!)),
            const SizedBox(height: 12),
            if (type == CompoundType.steroid) ...[_buildField("Ester", (v) => ester = v), const SizedBox(height: 12)],

            if (type == CompoundType.peptide || type == CompoundType.ancillary) ...[
              const Text("Visual Mode", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: GestureDetector(onTap: () => setState(() => graphType = GraphType.activeWindow), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: graphType == GraphType.activeWindow ? const Color(0xFF10B981) : const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)), child: const Center(child: Text("Active Window", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))))),
                const SizedBox(width: 8),
                Expanded(child: GestureDetector(onTap: () => setState(() => graphType = GraphType.event), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: graphType == GraphType.event ? const Color(0xFF10B981) : const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)), child: const Center(child: Text("Event Marker", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))))),
              ]),
              const SizedBox(height: 12)
            ],

            if (type == CompoundType.steroid || type == CompoundType.oral || (graphType == GraphType.activeWindow))
              Row(children: [
                Expanded(child: _buildField("Half Life (days)", (v) => halfLife = v, init: halfLife)),
                const SizedBox(width: 10),
                if (type == CompoundType.steroid || type == CompoundType.oral) Expanded(child: _buildField("Time to Peak", (v) => timeToPeak = v, init: timeToPeak)),
              ]),

            const SizedBox(height: 12),
            Row(children: [
              if (type == CompoundType.steroid) Expanded(child: _buildField("Yield %", (v) => ratio = v, init: ratio)),
              const SizedBox(width: 10),
              Expanded(child: _buildDropdown("Unit", unit, Unit.values, (v) => setState(() => unit = v!))),
            ]),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.all(16)), child: const Text("SAVE", style: TextStyle(color: Colors.white))))
          ],
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFF10B981), child: const Icon(Icons.add, color: Colors.white), onPressed: () => setState(() => isCreating = true)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.science, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text('My Compounds', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  color: const Color(0xFF1E293B),
                  onSelected: (value) {
                    if (value == 'export') widget.onExport();
                    if (value == 'import') widget.onImport();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'export', child: Text('Export Log to Clipboard')),
                    PopupMenuItem(value: 'import', child: Text('Import Log from Clipboard')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.userCompounds.length,
              itemBuilder: (c, i) {
                final comp = widget.userCompounds[i];
                return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(title: Text(comp.base, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text("${comp.ester} • ${comp.type.name.toUpperCase()}"), trailing: comp.isCustom == true ? IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => widget.onDelete(comp.id)) : null));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, Function(String) onChange, {String? init}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 4), TextFormField(initialValue: init, onChanged: onChange, style: const TextStyle(color: Colors.white), decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0F172A), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981)))))]);
  }

  Widget _buildDropdown<T>(String label, T value, List<T> items, Function(T?) onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 4),
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  items: items.map((e) {
                    String text = e.toString().split('.').last;
                    if (e is Unit) {
                      text = text.toLowerCase();
                    } else {
                      text = capitalize(text);
                    }
                    return DropdownMenuItem(value: e, child: Text(text));
                  }).toList(),
                  onChanged: onChanged
              )
          )
      )
    ]);
  }
}
