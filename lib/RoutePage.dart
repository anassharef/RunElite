import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Import for connectivity
import 'dart:async'; // Import for StreamSubscription
import 'package:uuid/uuid.dart'; // Import for UUID generation
import 'HomeScreen.dart';

class MapScreen extends StatefulWidget {
  final Map<String, dynamic>? routeData;

  MapScreen({this.routeData});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _controller;
  List<LatLng> _markers = [];
  Set<Polyline> _polylines = {};
  String apiKey = "AIzaSyB5DU5d30zQhhjxnBKht4uctFwOhEIoJAo"; // Replace with your Google Maps API key
  double? _totalDistance;
  TextEditingController _searchController = TextEditingController();
  TextEditingController _routeNameController = TextEditingController(); // Controller for route name
  List<Map<String, dynamic>> _savedRoutes = [];
  bool _isPublic = true; // Default route type is Public
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
          'name': _routeNameController.text, // Use the entered route name
          'area': _routeArea, // Save the route area
          'rating': 0.0, // Initialize the rating field
          'raters': 0, // Initialize the raters field
        });
      });
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error')));
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
          .showSnackBar(SnackBar(content: Text('Unavailable location')));
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
            .showSnackBar(SnackBar(content: Text('Error: Unknown Area')));
        print('Error fetching area: ${json['status']}');
      }
    } else {
      _routeArea = 'Unknown Area';
    }
  }

  Future<void> _saveToFirebase() async {
    if (_routeNameController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Please enter a route name.')));
      return;
    }

    await _determineArea(); // Ensure the area is determined before saving
    await _calculateRoute();

    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    CollectionReference routes =
        FirebaseFirestore.instance.collection('routes');
    CollectionReference userRoutes = FirebaseFirestore.instance
        .collection('userInfo')
        .doc(user!.uid)
        .collection('My Routes');

    if (_savedRoutes.isNotEmpty) {
      var lastRoute = _savedRoutes.last;
      lastRoute['area'] = _routeArea; // Add the area to the route

      // Save to user's routes
      await userRoutes.add(lastRoute);

      // Save to global routes if public
      if (lastRoute['type'] == 'Public') {
        await routes.add(lastRoute);
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Route Saved')));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No route to save')));
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
          Row(
            children: [
              Text(
                _isPublic ? 'Public' : 'Private',
                style: TextStyle(color: Colors.white),
              ),
              Switch(
                value: _isPublic,
                onChanged: (bool value) {
                  setState(() {
                    _isPublic = value;
                  });
                },
                activeColor: Color(0xFF4c6185), // Change this to your desired active color
                activeTrackColor: Color.fromARGB(255, 128, 146, 177), // Change this to your desired active track color
                inactiveThumbColor: Colors.grey, // Change this to your desired inactive thumb color
                inactiveTrackColor: Colors.grey[300], // Change this to your desired inactive track color
                ),
            ],
          ),
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
            top: 5, // Adjusted position for the Name text field
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
                controller: _routeNameController, // Route name input field
                decoration: InputDecoration(
                  hintText: 'Enter route name',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          Positioned(
            top: 60,
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
              top: 115,
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
                  style: TextStyle(color: Color.fromARGB(218, 255, 255, 255),fontFamily: 'Oswald'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
