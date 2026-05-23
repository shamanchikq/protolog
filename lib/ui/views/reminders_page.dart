import 'package:flutter/material.dart';
import '../../models.dart';
import '../../data.dart';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class RemindersPage extends StatefulWidget {
  final List<Reminder> reminders;
  final List<CompoundDefinition> userCompounds;
  final Function(List<Reminder>) onSave;
  final Function(Reminder) onSchedule;
  final Function(Reminder) onCancel;

  const RemindersPage({super.key, required this.reminders, required this.userCompounds, required this.onSave, required this.onSchedule, required this.onCancel});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  late List<Reminder> _reminders;
  bool _isAdding = false;
  String? _selectedBase;
  String? _selectedEster;
  String _scheduleMode = 'interval';
  String _intervalDays = '3';
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  // Custom mode state: which days are selected, and per-day time (AM/PM or custom)
  final Map<int, TimeOfDay> _customDayTimes = {}; // weekday (1-7) -> time
  // Compound selector state (category tabs + steroid drill-down)
  String _typeFilter = 'steroid';
  String? _selectedBaseForSteroid;

  @override
  void initState() {
    super.initState();
    _reminders = List.from(widget.reminders);
  }

  void _resetForm() {
    _selectedBase = null;
    _selectedEster = null;
    _scheduleMode = 'interval';
    _intervalDays = '3';
    _time = const TimeOfDay(hour: 10, minute: 0);
    _customDayTimes.clear();
    _typeFilter = 'steroid';
    _selectedBaseForSteroid = null;
  }

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

  List<CompoundDefinition> get _availableCompounds {
    final targetType = _typeFilter == 'steroid' ? CompoundType.steroid
        : _typeFilter == 'oral' ? CompoundType.oral
        : _typeFilter == 'peptide' ? CompoundType.peptide
        : CompoundType.ancillary;

    if (targetType == CompoundType.steroid) {
      if (_selectedBaseForSteroid != null) {
        final Map<String, CompoundDefinition> esters = {};
        for (var comp in widget.userCompounds) {
          if (comp.type == CompoundType.steroid && comp.base == _selectedBaseForSteroid && !esters.containsKey(comp.ester)) {
            esters[comp.ester] = comp;
          }
        }
        BASE_LIBRARY.forEach((key, val) {
          if (val.type == CompoundType.steroid && val.base == _selectedBaseForSteroid && !esters.containsKey(val.ester)) {
            esters[val.ester] = val;
          }
        });
        return esters.values.toList();
      }
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

  String _formatSchedule(Reminder r) {
    if (r.scheduleMode == 'custom' && r.customSlots.isNotEmpty) {
      // Check if all slots are weekdays at the same time
      final weekdaySlots = r.customSlots.where((s) => s.weekday >= 1 && s.weekday <= 5).toList();
      final allSameTime = r.customSlots.every((s) => s.hour == r.customSlots.first.hour && s.minute == r.customSlots.first.minute);
      if (weekdaySlots.length == 5 && r.customSlots.length == 5 && allSameTime) {
        return 'Weekdays at ${r.customSlots.first.hour.toString().padLeft(2, '0')}:${r.customSlots.first.minute.toString().padLeft(2, '0')}';
      }
      return r.customSlots.map((s) {
        final dayName = _dayNames[s.weekday - 1];
        final h = s.hour;
        return '$dayName ${h < 12 ? 'AM' : 'PM'}';
      }).join(', ');
    }
    final timeStr = '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
    return 'Every ${r.intervalDays} days at $timeStr';
  }

  void _saveReminder() {
    if (_selectedBase == null) return;

    List<ReminderSlot> slots = [];
    if (_scheduleMode == 'custom') {
      if (_customDayTimes.isEmpty) return;
      final sortedDays = _customDayTimes.keys.toList()..sort();
      for (var day in sortedDays) {
        final t = _customDayTimes[day]!;
        slots.add(ReminderSlot(weekday: day, hour: t.hour, minute: t.minute));
      }
    }

    final reminder = Reminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      compoundBase: _selectedBase!,
      compoundEster: _selectedEster ?? 'None',
      scheduleMode: _scheduleMode,
      intervalDays: int.tryParse(_intervalDays) ?? 3,
      hour: _time.hour,
      minute: _time.minute,
      customSlots: slots,
      enabled: true,
    );
    setState(() {
      _reminders.add(reminder);
      _isAdding = false;
    });
    _resetForm();
    widget.onSave(_reminders);
    widget.onSchedule(reminder);
  }

  void _toggleReminder(int index) {
    final r = _reminders[index];
    final updated = r.copyWith(enabled: !r.enabled);
    setState(() => _reminders[index] = updated);
    widget.onSave(_reminders);
    if (updated.enabled) {
      widget.onSchedule(updated);
    } else {
      widget.onCancel(updated);
    }
  }

  void _deleteReminder(int index) {
    final r = _reminders[index];
    widget.onCancel(r);
    setState(() => _reminders.removeAt(index));
    widget.onSave(_reminders);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Reminders'),
      ),
      floatingActionButton: _isAdding ? null : FloatingActionButton(
        backgroundColor: const Color(0xFF10B981),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => setState(() {
          _resetForm();
          _isAdding = true;
        }),
      ),
      body: _isAdding ? _buildAddForm() : _buildList(),
    );
  }

  Widget _buildList() {
    if (_reminders.isEmpty) {
      return const Center(child: Text('No reminders yet', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reminders.length,
      itemBuilder: (context, index) {
        final r = _reminders[index];
        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              '${r.compoundBase}${r.compoundEster != 'None' ? ' ${r.compoundEster}' : ''}',
              style: TextStyle(fontWeight: FontWeight.bold, color: r.enabled ? Colors.white : Colors.grey),
            ),
            subtitle: Text(_formatSchedule(r), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: r.enabled,
                  activeTrackColor: const Color(0xFF10B981),
                  onChanged: (_) => _toggleReminder(index),
                ),
                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.grey), onPressed: () => _deleteReminder(index)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
                if (_selectedBaseForSteroid != null) {
                  setState(() => _selectedBaseForSteroid = null);
                } else {
                  setState(() { _isAdding = false; _resetForm(); });
                }
              }),
              Text(_selectedBaseForSteroid ?? 'New Reminder', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          // Compound selector - category tabs
          if (_selectedBase == null) ...[
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
                    onTap: () => setState(() { _typeFilter = tab['key']!; _selectedBaseForSteroid = null; }),
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
              itemCount: _availableCompounds.length,
              itemBuilder: (c, i) {
                final compound = _availableCompounds[i];
                String displayName;
                String subtitle;
                if (_typeFilter == 'steroid' && _selectedBaseForSteroid == null) {
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
                    if (_typeFilter == 'steroid' && _selectedBaseForSteroid == null) {
                      if (_esterCountForBase(compound.base) == 1) {
                        setState(() {
                          _selectedBase = compound.base;
                          _selectedEster = compound.ester;
                        });
                      } else {
                        setState(() => _selectedBaseForSteroid = compound.base);
                      }
                    } else {
                      setState(() {
                        _selectedBase = compound.base;
                        _selectedEster = compound.ester;
                      });
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
            ),
          ],
          if (_selectedBase != null) ...[
            // Show selected compound chip with clear button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
              child: Row(
                children: [
                  Expanded(child: Text(
                    '$_selectedBase${_selectedEster != null && _selectedEster != 'None' ? ' $_selectedEster' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  )),
                  GestureDetector(
                    onTap: () => setState(() { _selectedBase = null; _selectedEster = null; _selectedBaseForSteroid = null; }),
                    child: const Icon(Icons.close, size: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
          if (_selectedBase != null) ...[
          const SizedBox(height: 20),
          // Schedule mode toggle
          const Text('Schedule Type', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                _modeTab('Interval', 'interval'),
                _modeTab('Custom Days', 'custom'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_scheduleMode == 'interval') ...[
            const Text('Interval (days)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(
              controller: TextEditingController(text: _intervalDays),
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => _intervalDays = v,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
                child: Row(children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(_time.format(context), style: const TextStyle(color: Colors.white)),
                ]),
              ),
            ),
          ],

          if (_scheduleMode == 'custom') ...[
            const Text('Select days and times', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            // Quick-select row
            Row(
              children: [
                _quickSelectBtn('Weekdays', () {
                  setState(() {
                    _customDayTimes.clear();
                    for (int d = 1; d <= 5; d++) {
                      _customDayTimes[d] = const TimeOfDay(hour: 10, minute: 0);
                    }
                  });
                }),
                const SizedBox(width: 8),
                _quickSelectBtn('MWF', () {
                  setState(() {
                    _customDayTimes.clear();
                    for (var d in [1, 3, 5]) {
                      _customDayTimes[d] = const TimeOfDay(hour: 10, minute: 0);
                    }
                  });
                }),
                const SizedBox(width: 8),
                _quickSelectBtn('TTS', () {
                  setState(() {
                    _customDayTimes.clear();
                    for (var d in [2, 4, 6]) {
                      _customDayTimes[d] = const TimeOfDay(hour: 10, minute: 0);
                    }
                  });
                }),
              ],
            ),
            const SizedBox(height: 12),
            // Day grid with toggles
            ...List.generate(7, (i) {
              final weekday = i + 1; // 1=Mon
              final isSelected = _customDayTimes.containsKey(weekday);
              final dayTime = _customDayTimes[weekday] ?? const TimeOfDay(hour: 10, minute: 0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _customDayTimes.remove(weekday);
                        } else {
                          _customDayTimes[weekday] = const TimeOfDay(hour: 10, minute: 0);
                        }
                      }),
                      child: Container(
                        width: 56,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? const Color(0xFF10B981) : const Color(0xFF334155)),
                        ),
                        child: Center(child: Text(_dayNames[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey))),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 10),
                      _amPmBtn('AM', weekday, dayTime, const TimeOfDay(hour: 10, minute: 0)),
                      const SizedBox(width: 6),
                      _amPmBtn('PM', weekday, dayTime, const TimeOfDay(hour: 22, minute: 0)),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: dayTime);
                          if (t != null) setState(() => _customDayTimes[weekday] = t);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: (dayTime.hour != 10 || dayTime.minute != 0) && (dayTime.hour != 22 || dayTime.minute != 0)
                                ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Text(dayTime.format(context), style: const TextStyle(fontSize: 12, color: Colors.white)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: (_scheduleMode == 'interval' || _customDayTimes.isNotEmpty) ? _saveReminder : null,
              child: const Text('SAVE REMINDER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          ],
        ],
      ),
    );
  }

  Widget _modeTab(String label, String mode) {
    final isActive = _scheduleMode == mode;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _scheduleMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: isActive ? const Color(0xFF334155) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Center(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey))),
      ),
    ));
  }

  Widget _quickSelectBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
        child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _amPmBtn(String label, int weekday, TimeOfDay current, TimeOfDay target) {
    final isActive = current.hour == target.hour && current.minute == target.minute;
    return GestureDetector(
      onTap: () => setState(() => _customDayTimes[weekday] = target),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF10B981) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? const Color(0xFF10B981) : const Color(0xFF334155)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey)),
      ),
    );
  }
}
