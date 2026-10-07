
import 'package:flutter/material.dart';
import 'database_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final helper = DatabaseHelper();

  try {
    await helper.init();
    runApp(FestivalApp(helper: helper));
  } catch (error, stackTrace) {
    debugPrint('Database initialization failed: $error\n$stackTrace');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Could not open local storage. Restart the app and check the logs.',
            ),
          ),
        ),
      ),
    );
  }
}

class FestivalApp extends StatelessWidget {
  final DatabaseHelper helper;

  const FestivalApp({super.key, required this.helper});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Festival Roster',
      debugShowCheckedModeBanner: false,
      home: FestivalScreen(helper: helper),
    );
  }
}

class FestivalScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const FestivalScreen({super.key, required this.helper});

  @override
  State<FestivalScreen> createState() => _FestivalScreenState();
}

class _FestivalScreenState extends State<FestivalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  int _count = 0;
  int? _editingId;

  bool _busy = false;
  bool _loading = true;
  String? _error;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<bool> _loadRows() async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await widget.helper.queryAllRows(),
      );
      final count = await widget.helper.queryRowCount();

      if (!mounted) return false;

      rows.sort((a, b) {
        final first = a[DatabaseHelper.columnId] as int;
        final second = b[DatabaseHelper.columnId] as int;
        return first.compareTo(second);
      });

      setState(() {
        _rows = rows;
        _count = count;
        _error = null;
      });

      return true;
    } catch (error, stackTrace) {
      debugPrint('Database read failed: $error\n$stackTrace');

      if (mounted) {
        setState(() {
          _error = 'Could not load guests. Tap Refresh to retry.';
        });
      }

      return false;
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _loading = true;
      _feedback = null;
    });

    try {
      await _loadRows();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a nonempty name';
    }
    return null;
  }

  String? _validateAge(String? value) {
    final age = int.tryParse(value?.trim() ?? '');

    if (age == null) {
      return 'Enter a whole-number age';
    }

    if (age < 0 || age > 130) {
      return 'Age must be between 0 and 130';
    }

    return null;
  }

  void _clearForm() {
    _nameController.clear();
    _ageController.clear();
    _formKey.currentState?.reset();
    _editingId = null;
  }

  void _edit(Map<String, dynamic> row) {
    if (_busy) return;

    setState(() {
      _editingId = row[DatabaseHelper.columnId] as int;
      _nameController.text =
          row[DatabaseHelper.columnName].toString();
      _ageController.text =
          row[DatabaseHelper.columnAge].toString();
      _feedback = null;
    });
  }

  void _cancelEdit() {
    if (_busy) return;

    setState(() {
      _clearForm();
      _feedback = 'Edit cancelled. No changes saved.';
    });
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final age = int.parse(_ageController.text.trim());
    final selectedId = _editingId;

    setState(() {
      _busy = true;
      _feedback = null;
    });

    try {
      int result;

      if (selectedId == null) {
        result = await widget.helper.insert({
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });
      } else {
        result = await widget.helper.update({
          DatabaseHelper.columnId: selectedId,
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });
      }

      if (!mounted) return;

      if (selectedId != null && result == 0) {
        setState(() {
          _feedback = 'Guest ID $selectedId no longer exists.';
        });
        await _loadRows();
        return;
      }

      setState(() {
        _clearForm();
      });

      final loaded = await _loadRows();

      if (!mounted) return;

      setState(() {
        _feedback = selectedId == null
            ? 'Guest saved with ID $result.'
            : 'Updated $result row for ID $selectedId.';

        if (!loaded) {
          _feedback = '${_feedback!} Saved, but refresh failed.';
        }
      });
    } catch (error, stackTrace) {
      debugPrint('Database write failed: $error\n$stackTrace');

      if (mounted) {
        setState(() {
          _feedback = 'Save failed. Check the logs and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (_busy) return;

    final id = row[DatabaseHelper.columnId] as int;
    final name = row[DatabaseHelper.columnName].toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete guest?'),
        content: Text('Delete $name (ID $id)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed != true) {
      setState(() {
        _feedback = 'Deletion cancelled. No records removed.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _feedback = null;
    });

    try {
      final deleted = await widget.helper.delete(id);

      if (!mounted) return;

      if (deleted > 0 && _editingId == id) {
        setState(_clearForm);
      }

      final loaded = await _loadRows();

      if (!mounted) return;

      setState(() {
        _feedback = deleted == 0
            ? 'Guest ID $id no longer exists.'
            : 'Deleted $deleted row for ID $id.';

        if (!loaded) {
          _feedback = '${_feedback!} Refresh failed; tap Refresh.';
        }
      });
    } catch (error, stackTrace) {
      debugPrint('Database delete failed: $error\n$stackTrace');

      if (mounted) {
        setState(() {
          _feedback = 'Delete failed. Check the logs and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Festival Roster'),
        backgroundColor: Colors.deepOrange.shade100,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Guest name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ageController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Guest age',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateAge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _busy ? null : _save,
                        child: Text(
                          _editingId == null ? 'Add Guest' : 'Save Edit',
                        ),
                      ),
                      if (_editingId != null)
                        OutlinedButton(
                          onPressed: _busy ? null : _cancelEdit,
                          child: const Text('Cancel Edit'),
                        ),
                      OutlinedButton(
                        onPressed: _busy ? null : _refresh,
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Record count: $_count',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_feedback!),
              ),
            const Divider(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _rows.isEmpty
                          ? const Center(
                              child: Text('No festival guests yet'),
                            )
                          : ListView.builder(
                              itemCount: _rows.length,
                              itemBuilder: (context, index) {
                                final row = _rows[index];
                                final id =
                                    row[DatabaseHelper.columnId] as int;
                                final name =
                                    row[DatabaseHelper.columnName];
                                final age =
                                    row[DatabaseHelper.columnAge];

                                return Card(
                                  child: ListTile(
                                    title: Text('$name (Age $age)'),
                                    subtitle: Text('Guest ID: $id'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit guest $id',
                                          onPressed: _busy
                                              ? null
                                              : () => _edit(row),
                                          icon: const Icon(Icons.edit),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete guest $id',
                                          onPressed: _busy
                                              ? null
                                              : () => _delete(row),
                                          icon: const Icon(Icons.delete),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
