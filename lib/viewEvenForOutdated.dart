import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'Events.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Import for connectivity
import 'dart:async'; // Import for StreamSubscription


class ViewEvent2Screen extends StatefulWidget {
  final String eventId;

  ViewEvent2Screen({required this.eventId});

  @override
  _ViewEvent2ScreenState createState() => _ViewEvent2ScreenState();
}

class _ViewEvent2ScreenState extends State<ViewEvent2Screen> {
  bool _isParticipating = false;
  late StreamSubscription<List<ConnectivityResult>> _subscription; // Subscription for connectivity changes
  bool _isDialogShowing = false; // Flag to track if the dialog is showing

  @override
  void initState() {
    super.initState();
    _checkIfUserIsParticipating();
    _listenToConnectivity(); // Start listening to connectivity changes
  }

  @override
  void dispose() {
    _subscription.cancel(); // Cancel the subscription when the widget is disposed
    super.dispose();
  }

  void _listenToConnectivity() {
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.none)) {
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
              content: Text("Please check your internet connection."),
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

  Future<void> _checkIfUserIsParticipating() async {
    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot eventSnapshot = await FirebaseFirestore.instance
          .collection('userInfo')
          .doc(user.uid)
          .collection('My Events')
          .doc(widget.eventId)
          .get();

      setState(() {
        _isParticipating = eventSnapshot.exists;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('userInfo')
          .doc(user!.uid)
          .collection('My Events')
          .doc(widget.eventId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Event Details'),
              backgroundColor: Color(0xFF4c6185),
            ),
            body: Center(child: CircularProgressIndicator(),),
            backgroundColor: Color(0xFFdbe4ee),);
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
           print('Event not found');
           return Scaffold(
            appBar: AppBar(
              title: Text('Event Details'),
              backgroundColor: Color(0xFF4c6185),
            ),
            body: Center(child: CircularProgressIndicator(),),
            backgroundColor: Color(0xFFdbe4ee),);
        }

        Event event = Event.fromMap(snapshot.data!.data() as Map<String, dynamic>);
        bool isOutdated = event.dateTime.isBefore(DateTime.now());
        String eventAreaa = getFirstTwoWords(event.eventArea);
        return Scaffold(
          appBar:AppBar(
          title: Text('Event Details'),
          backgroundColor: Color(0xFF4c6185),
          actions: [
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: _confirmDelete, // This will confirm before deleting
            ),
          ],
        ),
          backgroundColor: Color(0xFFdbe4ee),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                           SizedBox(height: 10),
              // Date and Time
              _buildDateTime(event),
              SizedBox(height: 10),
              // About the Event
              _buildAboutEvent(event),
              SizedBox(height: 10),
              // Location
              _buildLocation(eventAreaa),
              SizedBox(height: 10),
              // View Route Button
              _buildViewRouteButton(event),
              SizedBox(height: 10),
              // Number of Participants
              _buildParticipantsRow(event),
              SizedBox(height: 10),
              // Participants Dropdown
              _buildParticipantsDropdown(event),
              SizedBox(height: 10,),
              // Participation Button
              Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(height: 5,),
                      
                      SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: Text(
                                'Event Ended. ',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontStyle: FontStyle.italic,
                                  color: const Color.fromARGB(199, 0, 0, 0),
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis, // Optional: adds ellipsis to long text
                                maxLines: 2, // Optional: limit the number of lines
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed:  null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF4c6185),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child:  Icon(
                              _isParticipating ? Icons.check_circle : Icons.check_circle_outline,
                              color: _isParticipating ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              
            ],
          )
          )
        );
      },
    );
  }

  void _navigateToEditEvent(Event event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEventScreen(event: event),
      ),
    );
  }

  Future<void> _toggleParticipation(Event event) async {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? user = _auth.currentUser;
  if (user != null) {
    DocumentReference eventRef = FirebaseFirestore.instance
        .collection('userInfo')
        .doc(user.uid)
        .collection('My Events')
        .doc(event.id);

    String message;

    if (_isParticipating) {
      await eventRef.delete();
      setState(() {
        _isParticipating = false;
        event.participants--;
      });
      message = 'Event deleted from your events.';
    } else {
      await eventRef.set(event.toMap());
      setState(() {
        _isParticipating = true;
        event.participants++;
      });
      message = 'You are now participating in the event ! Event Saved';
    }

    await FirebaseFirestore.instance.collection('events').doc(event.id).update({
      'participants': event.participants,
    });

    // Displaying the Snackbar with the message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
        //backgroundColor: _isParticipating ? Colors.green : Colors.red,
      ),
    );
  }
}


  void _navigateToViewRoute(Map<String, dynamic> routeData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewRoute2Screen(routeData: routeData),
      ),
    );
  }

  String getFirstTwoWords(String text) {
    if (text.length > 40) {
      text = text.substring(0, 37) + '...';
      return text;
    } else {
      return text;
    }
  }

  Widget _buildEventName(Event event) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Text('Event Name:', style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color.fromARGB(199, 0, 0, 0))),
          SizedBox(width: 20),
          Text(event.name, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Color.fromARGB(255, 41, 92, 140))),
        ],
      ),
    );
  }

  Widget _buildDateTime(Event event) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildDateContainer('Date:', DateFormat('yyyy-MM-dd').format(event.dateTime)),
        _buildDateContainer('Starting Time:', DateFormat('kk:mm').format(event.dateTime)),
      ],
    );
  }

  Widget _buildDateContainer(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color.fromARGB(199, 0, 0, 0))),
          SizedBox(width: 5),
          Text(value, style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 41, 92, 140))),
        ],
      ),
    );
  }

  Widget _buildAboutEvent(Event event) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About the Event:', style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color.fromARGB(199, 0, 0, 0))),
          SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.all(5),
            child: Text(event.notes ?? 'No details provided for this event.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Color.fromARGB(255, 41, 92, 140))),
          ),
        ],
      ),
    );
  }

  Widget _buildLocation(String eventArea) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Location:', style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color.fromARGB(199, 0, 0, 0))),
          SizedBox(height: 5),
          Text(eventArea, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Color.fromARGB(255, 41, 92, 140)), softWrap: true, overflow: TextOverflow.visible),
        ],
      ),
    );
  }

  Widget _buildViewRouteButton(Event event) {
    return Center(
      child: SizedBox(
        width: 200,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF4c6185),
            foregroundColor: Color.fromARGB(225, 255, 255, 255),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            padding: EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () => _navigateToViewRoute(event.route),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on),
              SizedBox(width: 8),
              Text('View Route'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantsRow(Event event) {
  return Container(
    padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: Text(
            'Number of Participants:',
            style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color.fromARGB(199, 0, 0, 0)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '${event.participants}',  // Display the participant count directly from the event object
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
              color: Color.fromARGB(255, 41, 92, 140),
            ),
          ),
        ),
      ],
    ),
  );
}


Widget _buildParticipantsDropdown(Event event) {
  if (event.participantsIds.isEmpty) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        'No participants yet.',
        style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color.fromARGB(199, 0, 0, 0)),
      ),
    );
  }

  Future<List<DocumentSnapshot>> _participantsFuture = FirebaseFirestore.instance
      .collection('userInfo')
      .where(FieldPath.documentId, whereIn: event.participantsIds)
      .get()
      .then((snapshot) => snapshot.docs);

  return FutureBuilder<List<DocumentSnapshot>>(
    future: _participantsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return CircularProgressIndicator();
      }

      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            'No participants yet.',
            style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color.fromARGB(199, 0, 0, 0)),
          ),
        );
      }

      List<Map<String, dynamic>> participants = snapshot.data!.map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return {
          'username': data != null ? data['username'] as String : 'Unknown',
          'profilePictureUrl': data != null && data.containsKey('profileImageUrl')
              ? data['profileImageUrl'] as String
              : 'https://via.placeholder.com/150', // Default image URL
        };
      }).toList();

      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<Map<String, dynamic>>(
              isExpanded: true,
              hint: Text('Participants', style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic)),
              items: participants.map((participant) {
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: participant,
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: NetworkImage(participant['profilePictureUrl']),
                        radius: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        participant['username'],
                        style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                // Handle dropdown item selection
              },
            ),
          ],
        ),
      );
    },
  );
}

void _confirmDelete() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text("Delete Event"),
        content: Text("Are you sure you want to delete this event?"),
        actions: <Widget>[
          TextButton(
            child: Text("Cancel"),
            onPressed: () {
              Navigator.of(context).pop(); // Dismiss the dialog
            },
          ),
          TextButton(
            child: Text("Delete"),
            onPressed: () async {
              Navigator.of(context).pop(); // Dismiss the dialog
              await _deleteEvent(); // Call the delete method
            },
          ),
        ],
      );
    },
  );
}

Future<void> _deleteEvent() async {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? user = _auth.currentUser;

  if (user != null) {
    try {
      // Delete the event from the user's sub-collection
      await FirebaseFirestore.instance
          .collection('userInfo')
          .doc(user.uid)
          .collection('My Events')
          .doc(widget.eventId)
          .delete();

      // Optionally, navigate back after deletion
      Navigator.of(context).pop();
    } catch (e) {
      // Handle errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to delete the event."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
}


class ViewRoute2Screen extends StatefulWidget {
  final Map<String, dynamic> routeData;

  ViewRoute2Screen({required this.routeData});

  @override
  _ViewRoute2ScreenState createState() => _ViewRoute2ScreenState();
}

class _ViewRoute2ScreenState extends State<ViewRoute2Screen> {
  GoogleMapController? _mapController;
  bool _showMoveBackButton = false;
  LatLngBounds? _routeBounds;

  @override
  void initState() {
    super.initState();
    _calculateRouteBounds();
  }

  void _calculateRouteBounds() {
    List<LatLng> markers = (widget.routeData['markers'] as List)
        .map((point) => LatLng(point['lat'], point['lng']))
        .toList();

    if (markers.isNotEmpty) {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          markers.map((m) => m.latitude).reduce((a, b) => a < b ? a : b),
          markers.map((m) => m.longitude).reduce((a, b) => a < b ? a : b),
        ),
        northeast: LatLng(
          markers.map((m) => m.latitude).reduce((a, b) => a > b ? a : b),
          markers.map((m) => m.longitude).reduce((a, b) => a > b ? a : b),
        ),
      );
      setState(() {
        _routeBounds = bounds;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    List<LatLng> markers = (widget.routeData['markers'] as List)
        .map((point) => LatLng(point['lat'], point['lng']))
        .toList();

    Set<Polyline> polylines = {
      Polyline(
        polylineId: PolylineId('route'),
        points: markers,
        color: Colors.blue,
        width: 5,
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('View Route'),
        backgroundColor: Color(0xFF4c6185),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: markers.isNotEmpty ? markers.first : LatLng(0, 0),
              zoom: 14.0,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            onCameraMove: (CameraPosition position) {
              _onMapMoved();
            },
            markers: markers
                .map((marker) => Marker(
                      markerId: MarkerId(marker.toString()),
                      position: marker,
                    ))
                .toSet(),
            polylines: polylines,
            myLocationEnabled: true,
            zoomControlsEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            mapType: MapType.normal,
          ),
          Positioned(
            top: 10,
            left: 20,
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color.fromARGB(203, 255, 255, 255),
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
                'Total Distance: ${widget.routeData['totalDistance']} km',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
          if (_showMoveBackButton)
            Positioned(
              bottom: 60,
              left: 20,
              child: ElevatedButton(
                onPressed: () {
                  _moveBackToRoute(markers);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color.fromARGB(203, 255, 255, 255),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  shadowColor: Colors.black.withOpacity(0.2),
                ),
                child: Icon(Icons.location_on, color: Color.fromARGB(154, 0, 0, 0)),
              ),
            ),
        ],
      ),
    );
  }

  void _onMapMoved() async {
    if (_mapController != null && _routeBounds != null) {
      LatLngBounds visibleRegion = await _mapController!.getVisibleRegion();
      bool outOfBounds = !_routeBounds!.contains(visibleRegion.northeast) || !_routeBounds!.contains(visibleRegion.southwest);

      if (outOfBounds != _showMoveBackButton) {
        setState(() {
          _showMoveBackButton = outOfBounds;
        });
      }
    }
  }

  void _moveBackToRoute(List<LatLng> markers) {
    if (_mapController != null && markers.isNotEmpty) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              markers.map((m) => m.latitude).reduce((a, b) => a < b ? a : b),
              markers.map((m) => m.longitude).reduce((a, b) => a < b ? a : b),
            ),
            northeast: LatLng(
              markers.map((m) => m.latitude).reduce((a, b) => a > b ? a : b),
              markers.map((m) => m.longitude).reduce((a, b) => a > b ? a : b),
            ),
          ),
          100.0, // padding
        ),
      );
    }
  }

  
}