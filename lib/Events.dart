import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Import for connectivity
import 'dart:async'; // Import for StreamSubscription
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart'; // Import for DateFormat'
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';
import 'ViewEvent.dart';
import 'dart:math';
import 'package:workmanager/workmanager.dart';

class CreateEventScreen extends StatefulWidget {
  final Event? event; // Optional event parameter

  CreateEventScreen({this.event}); // Constructor to accept the event
  @override
  _CreateEventScreenState createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = false;
  String? _EventArea;
  String? _routeId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final User? _user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? _routeData;

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd'); // Define the date format
  final DateFormat _timeFormat = DateFormat('HH:mm'); // Define the time format

  final Uuid _uuid = Uuid();

  String _selectedRouteOption = 'Pick New Route'; // Default dropdown value
  List<Map<String, dynamic>> _publicRoutes = [];
  List<Map<String, dynamic>> _privateRoutes = [];

  @override
  void initState() {
    super.initState();
    _fetchRoutes();

    // Check if an existing event is passed, and prefill the fields if so
    if (widget.event != null) {
      _nameController.text = widget.event!.name;
      _selectedDate = widget.event!.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(widget.event!.dateTime);
      _dateController.text = _dateFormat.format(widget.event!.dateTime);
      _timeController.text = _timeFormat.format(widget.event!.dateTime);
      _notesController.text = widget.event!.notes ?? '';
      _EventArea = widget.event!.eventArea;
      _routeData = widget.event!.route;
    }

    _requestNotificationPermission(); // Request notification permission here
  }

  Future<void> _fetchRoutes() async {
    if (_user != null) {
      // Fetch public routes
      QuerySnapshot publicSnapshot = await FirebaseFirestore.instance.collection('routes').get();
      setState(() {
        _publicRoutes = publicSnapshot.docs.map((doc) => {
          ...doc.data() as Map<String, dynamic>,
          'id': doc.id,
        }).toList();
      });

      // Fetch private routes
      QuerySnapshot privateSnapshot = await FirebaseFirestore.instance
          .collection('userInfo')
          .doc(_user!.uid)
          .collection('My Routes')
          .get();
      setState(() {
        _privateRoutes = privateSnapshot.docs.map((doc) => {
          ...doc.data() as Map<String, dynamic>,
          'id': doc.id,
        }).toList();
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _pickRoute() async {
    final selectedRouteData = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PickRouteForEvent()),
    );

    if (selectedRouteData != null) {
      setState(() {
        _routeId = _uuid.v4();
        _routeData = {
          'id': _routeId,
          ...selectedRouteData,
        };
        _EventArea = selectedRouteData['area'];
      });
    } else {
      setState(() {
        _routeId = null;
        _routeData = null;
        _EventArea = null;
      });
    }
  }

  void _selectExistingRoute(Map<String, dynamic> routeData) {
    setState(() {
      _routeId = routeData['id'];
      _routeData = routeData;
      _EventArea = routeData['area'];
    });
  }

  Future<void> _pickDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        _dateController.text = _dateFormat.format(pickedDate);
      });
    }
  }

  Future<void> _pickTime() async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );

    if (pickedTime != null) {
      setState(() {
        _selectedTime = pickedTime;
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, pickedTime.hour, pickedTime.minute);
        _timeController.text = _timeFormat.format(dt);
      });
    }
  }

Future<void> _saveEvent() async {
  setState(() {
    _isLoading = true;
  });

  if (_formKey.currentState?.validate() == true && _user != null && _selectedDate != null && _selectedTime != null) {
    if (_routeData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a route')),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final dateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    // Generate a unique ID if creating a new event
    final eventId = widget.event?.id ?? FirebaseFirestore.instance.collection('events').doc().id;

    // Ensure the participantsIds list includes the creator
    List<String> participantsIds = widget.event?.participantsIds ?? [];
    if (!participantsIds.contains(_user!.uid)) {
      participantsIds.add(_user!.uid);
    }

    final event = {
      'id': eventId,
      'name': _nameController.text,
      'participants': widget.event != null ? widget.event!.participants : 1,
      'route': _routeData,
      'creatorEmail': _user!.email!,
      'dateTime': dateTime.toIso8601String(),
      'EventArea': _EventArea,
      'notes': _notesController.text,
      'participantsIds': participantsIds,  // Add the participantsIds list to the event data
    };

    try {
      if (widget.event == null) {
        await FirebaseFirestore.instance.collection('events').doc(eventId).set(event);
        await FirebaseFirestore.instance
            .collection('userInfo')
            .doc(_user!.uid)
            .collection('My Events')
            .doc(eventId)
            .set(event);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Event Saved')),
        );

        // Schedule the reminder notification for the creator
        _scheduleCreatorNotification(event);

        Navigator.pop(context, true);
      } else {
        // Cancel old notifications for participants
        await _cancelParticipantNotifications(widget.event!);

        await FirebaseFirestore.instance.collection('events').doc(eventId).update(event);
        await FirebaseFirestore.instance
            .collection('userInfo')
            .doc(_user!.uid)
            .collection('My Events')
            .doc(eventId)
            .update(event);

        // Notify participants that the event has been updated
        _notifyParticipantsOfChange(event);

        // Schedule new notifications for participants with the updated date and time
        _scheduleParticipantNotifications(event);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Event updated')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving event')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  } else {
    setState(() {
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Please fill in all fields')),
    );
  }
}

void _notifyParticipantsOfChange(Map<String, dynamic> event) async {
  // Fetch the username of the event creator
  String creatorUsername = await _fetchUsername(_user!.uid);

  final message = 'The event "${event['name']}" has been updated by $creatorUsername';

  for (String participantId in event['participantsIds']) {
    Workmanager().registerOneOffTask(
      "update_notification_${event['id']}_$participantId",
      "simpleTask",
      inputData: {
        'message': message,
        'showNotification': true, // Notification flag
      },
      initialDelay: Duration(seconds: 0), // Send the notification immediately
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(seconds: 10),
    );
  }
}

Future<String> _fetchUsername(String userId) async {
  DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
      .collection('userInfo')
      .doc(userId)
      .get();

  if (userSnapshot.exists) {
    return userSnapshot.get('username') ?? 'Someone'; // Default to 'Someone' if username is not available
  } else {
    return 'Someone'; // Default to 'Someone' if user document doesn't exist
  }
}



Future<void> _cancelParticipantNotifications(Event event) async {
  for (String participantId in event.participantsIds) {
    Workmanager().cancelByUniqueName("participant_${event.id}_$participantId");
  }
}

void _scheduleParticipantNotifications(Map<String, dynamic> event) {
  final eventTime = DateTime.parse(event['dateTime']);
  final reminderTime = eventTime.subtract(Duration(hours: 2));

  if (reminderTime.isAfter(DateTime.now())) {
    for (String participantId in event['participantsIds']) {
      Workmanager().registerOneOffTask(
        "participant_${event['id']}_$participantId",
        "simpleTask",
        inputData: {
          'message': 'The event "${event['name']}" is starting in 2 hours!',
          'showNotification': true, // Notification flag
        },
        initialDelay: reminderTime.difference(DateTime.now()),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
    }
  }
}


  void _scheduleCreatorNotification(Map<String, dynamic> event) {
    final eventTime = DateTime.parse(event['dateTime']);
    final reminderTime = eventTime.subtract(Duration(hours: 2));

    if (reminderTime.isAfter(DateTime.now())) {
      Workmanager().registerOneOffTask(
        "creator_${event['id']}",
        "simpleTask",
        inputData: {
          'message': 'Your event "${event['name']}" is starting in 2 hours!',
          'showNotification': true, // Notification flag
        },
        initialDelay: reminderTime.difference(DateTime.now()),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFdbe4ee),
      appBar: AppBar(
        title: Text(widget.event == null ? 'Create Event' : 'Edit Event'),
        actions: [
          IconButton(onPressed: _saveEvent, icon: Icon(Icons.save)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                SizedBox(height: 5),
                // First Row: Add Event Name and TextFormField
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          'Add Event Name:',
                          style: TextStyle(color: Colors.black, fontSize: 18),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0),
                          child: TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Event Name',
                              labelStyle: TextStyle(color: Color.fromARGB(117, 0, 0, 0), fontSize: 18),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFF4c6185)),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFF4c6185)),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            cursorColor: Colors.black,
                            maxLines: 1,
                            style: TextStyle(color: Colors.black, fontSize: 18),
                            validator: (value) {
                              if (value != null && value.length > 20) {
                                return 'Event Name too long';
                              }
                              if (value == null || value.isEmpty) {
                                return 'Please enter an Event Name';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                // Second Row: Date and Time Picker Fields
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Date and Starting Time for the Event:',
                        style: TextStyle(color: Colors.black, fontSize: 18),
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0),
                              child: TextFormField(
                                controller: _dateController,
                                decoration: InputDecoration(
                                  focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Color(0xFF4c6185)),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Color(0xFF4c6185)),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  labelText: 'Date',
                                  labelStyle: TextStyle(color: Color.fromARGB(117, 0, 0, 0), fontSize: 18),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.calendar_today),
                                    onPressed: _pickDate,
                                  ),
                                ),
                                readOnly: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please select a date';
                                  }
                                  final now = DateTime.now();
                                  if (_selectedDate != null) {
                                    if (_selectedDate!.isBefore(DateTime(now.year, now.month, now.day))) {
                                      return 'Invalid Date: Date cannot be in the past';
                                    }
                                    if (_selectedDate!.year == now.year &&
                                        _selectedDate!.month == now.month &&
                                        _selectedDate!.day == now.day) {
                                      if (_selectedTime != null && 
                                          (_selectedTime!.hour < now.hour || 
                                          (_selectedTime!.hour == now.hour && _selectedTime!.minute <= now.minute))) {
                                        return 'Invalid Time: Time cannot be in the past';
                                      }
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0),
                              child: TextFormField(
                                controller: _timeController,
                                decoration: InputDecoration(
                                  focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Color(0xFF4c6185)),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Color(0xFF4c6185)),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  labelText: 'Time',
                                  labelStyle: TextStyle(color: Color.fromARGB(117, 0, 0, 0), fontSize: 18),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.access_time),
                                    onPressed: _pickTime,
                                  ),
                                ),
                                readOnly: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please select a time';
                                  }
                                  final now = DateTime.now();
                                  if (_selectedDate != null && _selectedTime != null) {
                                    final selectedDateTime = DateTime(
                                      _selectedDate!.year,
                                      _selectedDate!.month,
                                      _selectedDate!.day,
                                      _selectedTime!.hour,
                                      _selectedTime!.minute,
                                    );
                                    if (selectedDateTime.isBefore(now)) {
                                      return 'Invalid Time';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                // Third Row: Route Selection Container with Dropdown and "View Route" Button
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Route for the Event:',
                        style: TextStyle(color: Colors.black, fontSize: 18),
                      ),
                      SizedBox(height: 10),
                      DropdownButton<String>(
                        value: _selectedRouteOption,
                        icon: Icon(Icons.arrow_drop_down),
                        iconSize: 24,
                        elevation: 16,
                        isExpanded: true,
                        style: TextStyle(color: Colors.black, fontSize: 18),
                        underline: Container(
                          height: 2,
                          color: Color(0xFF4c6185),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'Pick New Route',
                            child: Row(
                              children: [
                                Icon(Icons.add_location, color: const Color.fromARGB(255, 21, 70, 110)),
                                SizedBox(width: 10),
                                Text('Create new route'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Select Public Route',
                            child: Row(
                              children: [
                                Icon(Icons.public, color: const Color.fromARGB(255, 41, 113, 44)),
                                SizedBox(width: 10),
                                Text('Select from public routes'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Select Private Route',
                            child: Row(
                              children: [
                                Icon(Icons.lock, color: const Color.fromARGB(255, 141, 39, 32)),
                                SizedBox(width: 10),
                                Text('Select from your routes'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (String? newValue) async {
                          setState(() {
                            _selectedRouteOption = newValue!;
                          });

                          if (_selectedRouteOption == 'Pick New Route') {
                            await _pickRoute();
                          } else if (_selectedRouteOption == 'Select Public Route') {
                            _showRouteSelectionDialog(_publicRoutes);
                          } else if (_selectedRouteOption == 'Select Private Route') {
                            _showRouteSelectionDialog(_privateRoutes);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                // New Container for Notes
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(30),
                  ),
                                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About the Event:',
                        style: TextStyle(color: Colors.black, fontSize: 18),
                      ),
                      SizedBox(height: 10),
                      TextFormField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4c6185)),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4c6185)),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          labelText: 'Add description or notes',
                          labelStyle: TextStyle(color: Color.fromARGB(117, 0, 0, 0), fontSize: 18),
                        ),
                        maxLines: 2,
                        validator: (value) {
                          if (value != null && value.length > 100) {
                            return 'Notes too long';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                // Fourth Row: Update\Delete Event Button
                if (widget.event != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _isLoading ? null : _deleteEvent2,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 238, 214, 212), // Set button color for delete
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete, color: Colors.red), // Icon for delete
                              SizedBox(width: 8), // Space between icon and text
                              Text('Delete Event', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                        if (_isLoading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.3),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRouteSelectionDialog(List<Map<String, dynamic>> routes) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select a Route'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: routes.length,
              itemBuilder: (context, index) {
                String routeName = routes[index]['name'] ?? 'Route ${index + 1}';
                String area = routes[index]['area'] ?? 'Unknown area';
                return ListTile(
                  title: Text(routeName),
                  subtitle: Text(area),
                  onTap: () {
                    _selectExistingRoute(routes[index]);
                    Navigator.of(context).pop();  // Close the dialog
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteEvent2() async {
  if (widget.event != null) {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete this event? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // Cancel deletion
              },
              child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // Confirm deletion
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmDelete) {
      try {
        setState(() {
          _isLoading = true;
        });

        // Delete the event from Firestore
        await FirebaseFirestore.instance.collection('events').doc(widget.event!.id).delete();
        
        // Optionally delete the event from the user's personal collection
        if (_user != null) {
          await FirebaseFirestore.instance
              .collection('userInfo')
              .doc(_user!.uid)
              .collection('My Events')
              .doc(widget.event!.id)
              .delete();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Event deleted')),
        );

        // Navigate to '/home' or '/discover'
        Navigator.pushNamedAndRemoveUntil(context, '/home', (Route<dynamic> route) => false);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting event')),
        );
        print('Error deleting event: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
}

class Event {
  String id; // Add this line
  String name;
  int participants;
  Map<String, dynamic> route;
  String creatorEmail;
  DateTime dateTime;
  String eventArea;
  String? notes;
  List<String> participantsIds;


  Event({
    required this.id, // Add this line
    required this.name,
    required this.participants,
    required this.route,
    required this.creatorEmail,
    required this.dateTime,
    required this.eventArea,
    this.notes,
    required this.participantsIds,
  });

  // Convert Firestore Document to Event object
  factory Event.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id, // Use Firestore document ID as event ID
      name: data['name'] ?? '',
      participants: data['participants'] ?? 0,
      route: data['route'] ?? {},
      creatorEmail: data['creatorEmail'] ?? '',
      dateTime: (data['dateTime'] != null)
          ? DateTime.parse(data['dateTime'])
          : DateTime.now(),
      eventArea: data['EventArea'] ?? '',
      notes: data['notes'],
      participantsIds: List<String>.from(data['participantsIds'] ?? []),
    );
  }

  // Convert Event object to Map for saving to Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'participants': participants,
      'route': route,
      'creatorEmail': creatorEmail,
      'dateTime': dateTime.toIso8601String(),
      'EventArea': eventArea,
      'notes': notes,
      'participantsIds': participantsIds,
    };
  }

  static Event fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['id'] ?? '', // Add this line
      name: map['name'],
      participants: map['participants'],
      route: map['route'],
      creatorEmail: map['creatorEmail'],
      dateTime: DateTime.parse(map['dateTime']),
      eventArea: map['EventArea'],
      notes: map['notes'],
      participantsIds: List<String>.from(map['participantsIds'] ?? []),
    );
  }
}

class PickRouteForEvent extends StatefulWidget {
  final Map<String, dynamic>? routeData;

  PickRouteForEvent({this.routeData});

  @override
  _PickRouteForEventState createState() => _PickRouteForEventState();
}

class _PickRouteForEventState extends State<PickRouteForEvent> {
  GoogleMapController? _controller;
  List<LatLng> _markers = [];
  Set<Polyline> _polylines = {};
  String apiKey = "YOUR_GOOGLE_MAPS_API_KEY"; // Replace with your Google Maps API key
  double? _totalDistance;
  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _savedRoutes = [];
  bool _isPublic = false;
  String _routeArea = ''; // Default route area
  late StreamSubscription<List<ConnectivityResult>> _subscription; // Subscription for connectivity changes
  bool _isDialogShowing = false; // Flag to track if the dialog is showing

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _listenToConnectivity(); // Start listening to connectivity changes
    if (widget.routeData != null) {
      _loadSavedRoute(widget.routeData!);
    }
  }

  void _listenToConnectivity() {
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      ConnectivityResult result = results.last;
      if (result == ConnectivityResult.none) {
        _showNoConnectionDialog();
      } else {
        _hideNoConnectionDialog();
      }
    });
  }

  void _showNoConnectionDialog() {
    if (!_isDialogShowing) {
      _isDialogShowing = true;
      Future.delayed(Duration.zero, () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("Connection Lost"),
              content: Text("Check your connection"),
            );
          },
        );
      });
    }
  }

  void _hideNoConnectionDialog() {
    if (_isDialogShowing) {
      _isDialogShowing = false;
      Navigator.of(context, rootNavigator: true).pop('dialog');
    }
  }

  @override
  void dispose() {
    _subscription.cancel(); // Cancel the subscription when the widget is disposed
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    Position position = await Geolocator.getCurrentPosition();
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude), 15));
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
  }

  void _onTap(LatLng position) {
    setState(() {
      _markers.add(position);
    });
  }

  Future<void> _calculateRoute() async {
    if (_markers.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please add at least two points.')));
      return;
    }

    String baseUrl = 'https://maps.googleapis.com/maps/api/directions/json?';
    String origin =
        'origin=${_markers.first.latitude},${_markers.first.longitude}';
    String destination =
        'destination=${_markers.last.latitude},${_markers.last.longitude}';
    String waypoints = '';

    if (_markers.length > 2) {
      waypoints = 'waypoints=optimize:false|' +
          _markers
              .sublist(1, _markers.length - 1)
              .map((e) => '${e.latitude},${e.longitude}')
              .join('|');
    }

    String mode = 'mode=walking';
    String url = '$baseUrl$origin&$destination&$waypoints&$mode&key=$apiKey';

    var response = await http.get(Uri.parse(url));
    var json = jsonDecode(response.body);

    if (json['status'] == 'OK') {
      var points = PolylinePoints()
          .decodePolyline(json['routes'][0]['overview_polyline']['points']);
      var legs = json['routes'][0]['legs'];
      double totalDistance = 0.0;

      for (var leg in legs) {
        totalDistance += leg['distance']['value'];
      }

      setState(() {
        _polylines.clear();
        _polylines.add(Polyline(
          polylineId: PolylineId('route'),
          points:
              points.map((point) => LatLng(point.latitude, point.longitude)).toList(),
          color: Colors.blue,
          width: 5,
        ));
        _totalDistance = totalDistance / 1000;

        _savedRoutes.add({
          'routeId': Uuid().v4(), // Generate a unique routeId
          'markers': _markers
              .map((marker) => {'lat': marker.latitude, 'lng': marker.longitude})
              .toList(),
          'polyline': points
              .map((point) => {'lat': point.latitude, 'lng': point.longitude})
              .toList(),
          'totalDistance': _totalDistance,
          'type': _isPublic ? 'Public' : 'Private', // Use the current route type
          'name': 'Event Route', // Use the entered route name
          'area': _routeArea, // Save the route area
        });
      });
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error fetching route, try again')));
      print('Error fetching directions: ${json['status']}');
    }
  }

  Future<void> _searchLocation(String query) async {
    String url =
        'https://maps.googleapis.com/maps/api/geocode/json?address=$query&key=$apiKey';
    var response = await http.get(Uri.parse(url));
    var json = jsonDecode(response.body);

    if (json['status'] == 'OK') {
      var location = json['results'][0]['geometry']['location'];
      LatLng latLng = LatLng(location['lat'], location['lng']);
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15)); // Zoom in when moving to the searched location
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unavailable Location')));
      print('Error fetching location: ${json['status']}');
    }
  }

  void _loadSavedRoute(Map<String, dynamic> routeData) {
    if (routeData['markers'] == null) {
      return;
    }

    List<LatLng> markers = (routeData['markers'] as List)
        .map((point) => LatLng(point['lat'], point['lng']))
        .toList();
    List<LatLng> polyline = (routeData['polyline'] as List)
        .map((point) => LatLng(point['lat'], point['lng']))
        .toList();
    double totalDistance = routeData['totalDistance'];

    setState(() {
      _markers = markers;
      _polylines.add(Polyline(
        polylineId: PolylineId('route'),
        points: polyline,
        color: Colors.blue,
        width: 5,
      ));
      _totalDistance = totalDistance;
    });

    _controller?.animateCamera(CameraUpdate.newLatLngZoom(_markers.first, 12));
  }

  Future<void> _determineArea() async {
    if (_markers.isNotEmpty) {
      String url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${_markers.first.latitude},${_markers.first.longitude}&key=$apiKey';
      var response = await http.get(Uri.parse(url));
      var json = jsonDecode(response.body);

      if (json['status'] == 'OK') {
        _routeArea = json['results'][0]['formatted_address'];
      } else {
        _routeArea = 'Unknown Area';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unavailable Location')));
        print('Error fetching area: ${json['status']}');
      }
    } else {
      _routeArea = 'Unknown Area';
    }
  }

  Future<void> _saveToFirebase() async {
    await _determineArea(); // Ensure the area is determined before saving
    await _calculateRoute();

    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    CollectionReference routes =
        FirebaseFirestore.instance.collection('routes');

    if (_savedRoutes.isNotEmpty) {
      var lastRoute = _savedRoutes.last;
      lastRoute['area'] = _routeArea; // Add the area to the route
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Route Saved')));
      Navigator.pop(context, lastRoute);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No Route To Save')));
    }
  }

  void _undoLastMarker() {
    setState(() {
      if (_markers.isNotEmpty) {
        _markers.removeLast();
        _polylines.clear();
        _totalDistance = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Route Planner'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _saveToFirebase,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            onTap: _onTap,
            markers: _markers.asMap().entries.map((entry) {
              int idx = entry.key;
              LatLng position = entry.value;
              return Marker(
                markerId: MarkerId(position.toString()),
                position: position,
                icon: idx == 0
                    ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
                    : BitmapDescriptor.defaultMarker,
              );
            }).toSet(),
            polylines: _polylines,
            initialCameraPosition: CameraPosition(
              target: LatLng(37.7749, -122.4194),
              zoom: 10.0,
            ),
          ),
          Positioned(
            top: 15,
            left: 20,
            right: 20,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Enter country or city name',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.search),
                    onPressed: () {
                      _searchLocation(_searchController.text);
                    },
                  ),
                ),
                onSubmitted: (value) {
                  _searchLocation(value);
                },
              ),
            ),
          ),
          if (_totalDistance != null)
            Positioned(
              top: 75,
              left: 20,
              right: 20,
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  'Total Distance: ${_totalDistance!.toStringAsFixed(2)} km',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Stack(
        children: [
          _markers.isNotEmpty
              ? Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 30.0, bottom: 16.0),
                    child: FloatingActionButton(
                      backgroundColor: Color(0xFF4c6185) ,
                      onPressed: _undoLastMarker,
                      heroTag: 'undoLastMarker', // Unique hero tag
                      child: Icon(Icons.undo, color: Color.fromARGB(218, 255, 255, 255))
                    ),
                  ),
                )
              : Container(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(left: 30.0, bottom: 16.0),
              child: ElevatedButton(
                onPressed: _calculateRoute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF4c6185),
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 12),
                  textStyle: TextStyle(fontSize: 16),
                ),
                child: Text(
                  'Calculate Route',
                  style: TextStyle(color: Color.fromARGB(218, 255, 255, 255), fontFamily: 'Oswald'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

               