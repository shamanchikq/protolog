import 'package:flutter/material.dart';
import '../../models.dart';
import '../../data.dart';
import '../../utils.dart';

class AddInjectionWizard extends StatefulWidget {
  final Function(Injection) onAdd;
  final VoidCallback onCancel;
  final VoidCallback onSuccess;
  final List<CompoundDefinition> userCompounds;
  final Function(CompoundDefinition) addUserCompound;
  final List<Injection> injections;

  const AddInjectionWizard({super.key, required this.onAdd, required this.onCancel, required this.onSuccess, required this.userCompounds, required this.addUserCompound, required this.injections});

  @override
  State<AddInjectionWizard> createState() => _AddInjectionWizardState();
}

class _AddInjectionWizardState extends State<AddInjectionWizard> {
  int step = 1;
  CompoundDefinition? selectedCompound;
  String dose = '';
  Unit unit = Unit.mg;
  DateTime date = DateTime.now();
  TimeOfDay time = TimeOfDay.now();
  bool calcMode = false;
  String concentration = '';
  String volume = '';
  String _typeFilter = 'steroid';
  String? _selectedBase;
  Injection? _lastForCompound;

  int _esterCountForBase(String base) {
    final Set<String> esters = {};
    for (var comp in widget.userCompounds) {
      if (comp.type == CompoundType.steroid && comp.base == base) esters.add(comp.ester);
    }
    BASE_LIBRARY.forEach((key, val) {
      if (val.type == CompoundType.steroid && val.base == base) esters.add(val.ester);
    });
    return esters.length;
  }

  List<CompoundDefinition> get availableCompounds {
    final targetType = _typeFilter == 'steroid' ? CompoundType.steroid
        : _typeFilter == 'oral' ? CompoundType.oral
        : _typeFilter == 'peptide' ? CompoundType.peptide
        : CompoundType.ancillary;

    if (targetType == CompoundType.steroid) {
      if (_selectedBase != null) {
        // Show esters for selected base, recently used first
        final Map<String, CompoundDefinition> esters = {};
        for (var comp in widget.userCompounds) {
          if (comp.type == CompoundType.steroid && comp.base == _selectedBase && !esters.containsKey(comp.ester)) {
            esters[comp.ester] = comp;
          }
        }
        BASE_LIBRARY.forEach((key, val) {
          if (val.type == CompoundType.steroid && val.base == _selectedBase && !esters.containsKey(val.ester)) {
            esters[val.ester] = val;
          }
        });
        return esters.values.toList();
      }
      // Show unique base names, recently used first
      final Map<String, CompoundDefinition> bases = {};
      for (var comp in widget.userCompounds) {
        if (comp.type == CompoundType.steroid && !bases.containsKey(comp.base)) {
          bases[comp.base] = comp;
        }
      }
      BASE_LIBRARY.forEach((key, val) {
        if (val.type == CompoundType.steroid && !bases.containsKey(val.base)) {
          bases[val.base] = val;
        }
      });
      return bases.values.toList();
    }

    // Non-steroid: flat list, recently used first
    final Map<String, CompoundDefinition> compounds = {};
    for (var comp in widget.userCompounds) {
      if (comp.type == targetType && !compounds.containsKey(comp.base)) {
        compounds[comp.base] = comp;
      }
    }
    BASE_LIBRARY.forEach((key, val) {
      if (val.type == targetType && !compounds.containsKey(val.base)) {
        compounds[val.base] = val;
      }
    });
    return compounds.values.toList();
  }

  void _onCompoundSelected(CompoundDefinition compound) {
    final matches = widget.injections
        .where((i) => i.snapshot.base == compound.base && i.snapshot.ester == compound.ester)
        .toList()..sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      selectedCompound = compound;
      unit = compound.unit;
      _lastForCompound = matches.isNotEmpty ? matches.first : null;
      if (_lastForCompound != null) {
        dose = _lastForCompound!.dosage.toString();
      }
      step = 2;
    });
  }

  void _goBack() {
    if (_selectedBase != null && step == 1) {
      setState(() => _selectedBase = null);
    } else {
      setState(() { step = 1; _selectedBase = null; _lastForCompound = null; });
    }
  }

  void _submit() {
    if (selectedCompound == null) return;
    final DateTime fullDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    var compDef = widget.userCompounds.firstWhere(
            (c) => c.base == selectedCompound!.base && c.ester == selectedCompound!.ester,
        orElse: () {
          final newComp = CompoundDefinition(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            base: selectedCompound!.base,
            ester: selectedCompound!.ester,
            type: selectedCompound!.type,
            graphType: selectedCompound!.graphType,
            halfLife: selectedCompound!.halfLife,
            defaultHalfLife: selectedCompound!.defaultHalfLife,
            timeToPeak: selectedCompound!.timeToPeak,
            ratio: selectedCompound!.ratio,
            unit: unit,
            colorValue: selectedCompound!.colorValue,
          );
          widget.addUserCompound(newComp);
          return newComp;
        }
    );

    widget.onAdd(Injection(id: DateTime.now().toIso8601String(), compoundId: compDef.id, date: fullDate, dosage: double.parse(dose), snapshot: compDef));
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (step > 1 || _selectedBase != null) IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack),
              Text(step == 1 ? (_selectedBase ?? "Select Compound") : "Details", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel)
            ],
          ),
          const SizedBox(height: 16),

          if (step == 1) ...[
            // Filter tabs
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  {'key': 'steroid', 'label': 'Injectable'},
                  {'key': 'oral', 'label': 'Oral'},
                  {'key': 'peptide', 'label': 'Peptide'},
                  {'key': 'ancillary', 'label': 'Ancillary'},
                ].map((tab) {
                  final isActive = _typeFilter == tab['key'];
                  return Expanded(child: GestureDetector(
                    onTap: () => setState(() { _typeFilter = tab['key']!; _selectedBase = null; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: isActive ? const Color(0xFF334155) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                      child: Center(child: Text(tab['label']!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey))),
                    ),
                  ));
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: availableCompounds.length,
              itemBuilder: (c, i) {
                final compound = availableCompounds[i];
                String displayName;
                String subtitle;
                if (_typeFilter == 'steroid' && _selectedBase == null) {
                  displayName = compound.base;
                  final count = _esterCountForBase(compound.base);
                  subtitle = '$count ${count == 1 ? 'variant' : 'variants'}';
                } else if (compound.type == CompoundType.steroid) {
                  displayName = compound.ester;
                  subtitle = 'HL: ${compound.halfLife}d';
                } else {
                  displayName = compound.base;
                  subtitle = compound.type.name.toUpperCase();
                }
                return GestureDetector(
                  onTap: () {
                    if (_typeFilter == 'steroid' && _selectedBase == null) {
                      if (_esterCountForBase(compound.base) == 1) {
                        _onCompoundSelected(compound);
                      } else {
                        setState(() => _selectedBase = compound.base);
                      }
                    } else {
                      _onCompoundSelected(compound);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF334155))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                        Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              },
            )
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF334155))),
                    child: Column(
                      children: [
                        Text(
                          selectedCompound!.type == CompoundType.steroid
                              ? '${selectedCompound!.base} ${selectedCompound!.ester}'.trim()
                              : selectedCompound!.base,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(selectedCompound!.colorValue)),
                        ),
                        const SizedBox(height: 4),
                        Text(selectedCompound!.type.name.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                  if (_lastForCompound != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Last: ${_lastForCompound!.dosage} ${_lastForCompound!.snapshot.unit.toString().split('.').last} — ${formatDate(_lastForCompound!.date, 'MMM d')}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
                      ),
                    ),
                  const SizedBox(height: 24),

                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton.icon(icon: const Icon(Icons.calculate, size: 16), label: Text(calcMode ? "Manual Entry" : "Calc by Volume"), onPressed: () => setState(() => calcMode = !calcMode))]),

                  if (calcMode)
                    Row(children: [Expanded(child: _styledInput("Conc (mg/ml)", concentration, (v) { setState(() { concentration = v; dose = ((double.tryParse(v)??0) * (double.tryParse(volume)??0)).toString(); }); })), const SizedBox(width: 10), Expanded(child: _styledInput("Vol (ml)", volume, (v) { setState(() { volume = v; dose = ((double.tryParse(concentration)??0) * (double.tryParse(v)??0)).toString(); }); }))]),

                  const SizedBox(height: 10),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _styledInput("Dosage", dose, (v) => setState(() => dose = v), readOnly: calcMode)),
                      const SizedBox(width: 10),
                      Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Unit>(
                            value: unit,
                            dropdownColor: const Color(0xFF1E293B),
                            items: Unit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.name.toLowerCase()))).toList(),
                            onChanged: (u) => setState(() => unit = u!),
                          ),
                        ),
                      )
                    ],
                  ),

                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => time = const TimeOfDay(hour: 10, minute: 0)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: time.hour == 10 && time.minute == 0 ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Center(child: Text('AM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => time = const TimeOfDay(hour: 22, minute: 0)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: time.hour == 22 && time.minute == 0 ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Center(child: Text('PM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDate: date); if (d != null) setState(() => date = d); }, child: _fakeInput(Icons.calendar_today, formatDate(date, 'yyyy-MM-dd')))),
                    const SizedBox(width: 10),
                    Expanded(child: InkWell(onTap: () async { final t = await showTimePicker(context: context, initialTime: time); if (t != null) setState(() => time = t); }, child: _fakeInput(Icons.access_time, time.format(context)))),
                  ]),

                  const SizedBox(height: 30),
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 16)), icon: const Icon(Icons.check, color: Colors.white), label: const Text("CONFIRM ENTRY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: dose.isNotEmpty ? _submit : null))
                ],
              ),
            )
          ]
        ],
      ),
    );
  }

  Widget _styledInput(String label, String value, Function(String) onChanged, {bool readOnly = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 4), TextField(controller: TextEditingController(text: value)..selection = TextSelection.fromPosition(TextPosition(offset: value.length)), onChanged: onChanged, readOnly: readOnly, keyboardType: TextInputType.number, style: TextStyle(color: readOnly ? Colors.grey : Colors.white), decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0F172A), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981))), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)))]);
  }

  Widget _fakeInput(IconData icon, String text) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))), child: Row(children: [Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(text, style: const TextStyle(color: Colors.white))]));
  }
}
