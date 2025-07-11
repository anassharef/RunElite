import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'HomeScreen.dart';
import 'UserStatus_Firebase.dart';

class ViewRouteScreen extends StatefulWidget {
  final Map<String, dynamic> routeData;

  ViewRouteScreen({required this.routeData});

  @override
  _ViewRouteScreenState createState() => _ViewRouteScreenState();
}

class _ViewRouteScreenState extends State<ViewRouteScreen> {
  bool _routeStarted = false;
  bool _isTrackingUser = false; // Flag to track user's location
  bool _isLoading = false; // Flag to show loading indicator
  bool _isDoneLoading = false; // Flag to show done loading indicator
  bool _isMovingToCurrentLocation = true; // Track button state
  
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<List<ConnectivityResult>>? _subscription; // Subscription for connectivity changes
  bool _isDialogShowing = false; // Flag to track if the dialog is showing
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Fields for steps and calories calculation
  int _steps = 0;
  double _caloriesBurned = 0;
  double _userWeight = 70.0; // Example weight in kg (this should be fetched from user data)
  double _averageStepLength = 0.75; // Average step length in meters

  double _globalRating = 0.0;
  int _globalRaters = 0;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _listenToConnectivity(); // Start listening to connectivity changes
    _calculateStepsAndCalories();

    // Fetch the rating and raters from the global collection if the route is public
    if (widget.routeData['type'] == 'Public') {
      _fetchGlobalRatingAndRaters();
    }
  }

  void _fetchGlobalRatingAndRaters() async {
    CollectionReference routes = FirebaseFirestore.instance.collection('routes');
    QuerySnapshot query = await routes.where('routeId', isEqualTo: widget.routeData['routeId']).get();

    if (query.docs.isNotEmpty) {
      DocumentSnapshot globalRouteDoc = query.docs.first;

      if (mounted) {
        setState(() {
          _globalRating = globalRouteDoc['rating'] ?? 0.0;
          _globalRaters = globalRouteDoc['raters'] ?? 0;
        });
      }
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
    _positionStream?.cancel();
    _subscription?.cancel(); // Cancel the subscription when the widget is disposed
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // update location if user moves 10 meters
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
      });
      if (_isTrackingUser && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
      }
    });
  }

  Future<void> _moveToCurrentLocation() async {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
      );
    }
  }

  void _moveBackToRoute(LatLng startPoint) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(startPoint.latitude, startPoint.longitude),
        ),
      );
    }
  }

  Future<void> _initializeUserStatsIfMissing() async {
    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentReference userDoc = FirebaseFirestore.instance.collection('userInfo').doc(user.uid);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(userDoc);
        if (!snapshot.exists) {
          throw Exception("User does not exist!");
        }

        Map<String, dynamic> userData = snapshot.data() as Map<String, dynamic>;

        if (!userData.containsKey('Calories Burned')) {
          transaction.update(userDoc, {
            'Calories Burned': 0.0,
          });
        }

        if (!userData.containsKey('Steps Taken')) {
          transaction.update(userDoc, {
            'Steps Taken': 0,
          });
        }
      });
    }
  }

  Future<void> _updateUserStats(double distance, double caloriesBurned, int stepsTaken) async {
    await _initializeUserStatsIfMissing(); // Ensure fields are present before updating

    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentReference userDoc = FirebaseFirestore.instance.collection('userInfo').doc(user.uid);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(userDoc);
        if (!snapshot.exists) {
          throw Exception("User does not exist!");
        }

        // Update the stats
        double newDistance = (snapshot.data() as Map<String, dynamic>)['Total Distance']?.toDouble() ?? 0.0;
        double newCalories = (snapshot.data() as Map<String, dynamic>)['Calories Burned']?.toDouble() ?? 0.0;
        int newSteps = (snapshot.data() as Map<String, dynamic>)['Steps Taken'] ?? 0;

        newDistance += distance;
        newCalories += caloriesBurned;
        newSteps += stepsTaken;

        transaction.update(userDoc, {
          'Total Distance': newDistance,
          'Calories Burned': newCalories,
          'Steps Taken': newSteps,
        });
      });
    }
  }

  Future<void> _navigateToHome() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
        (Route<dynamic> route) => false,
      );
    });
  }

  Future<void> _refreshUserData() async {
    await Provider.of<UserState>(context, listen: false).refreshUserData(); // Refresh user data
  }

  Future<void> _checkProximityAndStart(LatLng startPoint) async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        startPoint.latitude,
        startPoint.longitude,
      );

      if (distance > 5000) {
        // Further than 5km
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("Your GPS doesn't seem to be working so we'll trust you"),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _routeStarted = true;
                    });
                    ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
                      SnackBar(
                        content: Text('Started'),
                        duration: Duration(seconds: 2), // Set duration to 2 seconds
                      ),
                    );
                  },
                  child: Text('I understand'),
                ),
              ],
            );
          },
        );
      } else if (distance > 70) {
        // Within 5km but further than 70 meters
        ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text('Get closer to the start point'),
            duration: Duration(seconds: 2), // Set duration to 2 seconds
          ),
        );
      } else {
        // Within 70 meters
        setState(() {
          _routeStarted = true;
        });
        ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text('Started'),
            duration: Duration(seconds: 2), // Set duration to 2 seconds
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
        SnackBar(
          content: Text('Error getting location: $e'),
          duration: Duration(seconds: 2), // Set duration to 2 seconds
        ),
      );
    }
  }

  Future<void> _checkProximityAndFinish(LatLng endPoint, double totalDistance, String routeName) async {
    if (_isDoneLoading) return; // Prevent multiple presses
    setState(() {
      _isDoneLoading = true; // Show done loading indicator
    });

    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        endPoint.latitude,
        endPoint.longitude,
      );

      double maxAllowedDistance = totalDistance > 5.0 ? totalDistance * 1000 : 5000; // Calculate max distance in meters

      if (distance > maxAllowedDistance) {
        // Further than max allowed distance
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("We trust that you finished the route"),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _updateUserStats(totalDistance, _caloriesBurned, _steps);
                    await _refreshUserData();
                    ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
                      SnackBar(
                        content: Text('Congratulations! You completed $routeName!'),
                        duration: Duration(seconds: 2), // Set duration to 2 seconds
                      ),
                    );
                    await Future.delayed(Duration(seconds: 4)); // Delay for the SnackBar to show
                    if (widget.routeData['type'] == 'Public') {
                      await _showRatingDialog(); // Show the rating dialog after finishing the route
                    }
                    _navigateToHome();
                  },
                  child: Text('I understand'),
                ),
              ],
            );
          },
        );
      } else if (distance > 70) {
        // Within max allowed distance but further than 70 meters
        ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text("You're not done yet"),
            duration: Duration(seconds: 2), // Set duration to 2 seconds
          ),
        );
        setState(() {
          _isDoneLoading = false; // Hide done loading indicator if user needs to get closer
        });
      } else {
        // Within 70 meters
        await _updateUserStats(totalDistance, _caloriesBurned, _steps);
        await _refreshUserData();
        ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text('Congratulations! You completed $routeName!'),
            duration: Duration(seconds: 2), // Set duration to 2 seconds
          ),
        );
        await Future.delayed(Duration(seconds: 2)); // Delay for the SnackBar to show
        if (widget.routeData['type'] == 'Public') {
          await _showRatingDialog(); // Show the rating dialog after finishing the route
        }
        _navigateToHome();
      }
    } catch (e) {
      ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(
        SnackBar(
          content: Text('Error getting location'),
          duration: Duration(seconds: 2), // Set duration to 2 seconds
        ),
      );
      setState(() {
        _isDoneLoading = false; // Hide done loading indicator on error
      });
    }
  }

  Future<void> _showRatingDialog() async {
    double newRating = 0.0;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Rate this route'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please rate the route you just completed:'),
              SizedBox(height: 10),
              RatingBar.builder(
                initialRating: 0,
                minRating: 1,
                direction: Axis.horizontal,
                allowHalfRating: true,
                itemCount: 5,
                itemBuilder: (context, _) => Icon(
                  Icons.star,
                  color: Colors.amber,
                ),
                onRatingUpdate: (rating) {
                  newRating = rating;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog without doing anything
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _updateRating(newRating);
                Navigator.of(context).pop(); // Close the dialog
              },
              child: Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateRating(double userRating) async {
    if (widget.routeData['type'] != 'Public') return; // Only update for public routes

    try {
      // Update the rating in the global collection only
      CollectionReference routes = FirebaseFirestore.instance.collection('routes');
      QuerySnapshot query = await routes.where('routeId', isEqualTo: widget.routeData['routeId']).get();

      if (query.docs.isNotEmpty) {
        DocumentReference globalRouteDoc = query.docs.first.reference;
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          DocumentSnapshot snapshot = await transaction.get(globalRouteDoc);

          if (!snapshot.exists) {
            throw Exception("Route does not exist!");
          }

          Map<String, dynamic> routeData = snapshot.data() as Map<String, dynamic>;
          double currentRating = routeData['rating'] ?? 0.0;
          int raters = routeData['raters'] ?? 0;

          // Calculate the new rating
          double newRating = ((currentRating * raters) + userRating) / (raters + 1);

          transaction.update(globalRouteDoc, {
            'rating': newRating,
            'raters': raters + 1,
          });
        });

        // Update the global rating and raters count
        _fetchGlobalRatingAndRaters();
      }
    } catch (e) {
      print("Transaction failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error updating route rating"))
      );
    }
  }

  void _calculateStepsAndCalories() {
    double totalDistanceMeters = widget.routeData['totalDistance'] * 1000; // Convert km to meters
    _steps = (totalDistanceMeters / _averageStepLength).toInt();

    // Assuming a walking MET of 3.5
    double MET = 3.5;
    double timeInHours = totalDistanceMeters / 5000; // Assuming average speed of 5km/h
    _caloriesBurned = MET * _userWeight * timeInHours;

    setState(() {
      // Calculated steps and calories will be updated in Firestore when the route is completed
    });
  }

  @override
  Widget build(BuildContext context) {
    List<LatLng> markers = (widget.routeData['markers'] as List)
        .map((point) => LatLng(point['lat'], point['lng']))
        .toList();
    List<LatLng> polyline = (widget.routeData['polyline'] as List)
        .map((point) => LatLng(point['lat'], point['lng']))
        .toList();
    double totalDistance = widget.routeData['totalDistance'] ?? 0.0;
    String routeName = widget.routeData['name'] ?? 'Unnamed Route';
    LatLng startPoint = markers.first;
    LatLng endPoint = markers.last;

    double rating = _globalRating;
    int raters = _globalRaters;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(routeName),
        backgroundColor: Color(0xFF4c6185),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: startPoint,
              zoom: 14.0,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            markers: markers.asMap().entries.map((entry) {
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
            polylines: {
              Polyline(
                polylineId: PolylineId('route'),
                points: polyline,
                color: Colors.blue,
                width: 5,
              ),
            },
            myLocationEnabled: true,
            zoomControlsEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            mapType: MapType.normal,
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Column(
              children: [
                Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color.fromARGB(210, 255, 255, 255),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(199, 0, 0, 0).withOpacity(0.2),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Text(
                'Total Distance: ${totalDistance.toStringAsFixed(2)} km',
                style: TextStyle(fontSize: 16),
              ),
            ),
            SizedBox(height: 3),
            if (widget.routeData['type'] == 'Public')
              Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color.fromARGB(210, 255, 255, 255),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(199, 0, 0, 0).withOpacity(0.2),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  RatingBarIndicator(
                    rating: rating,
                    itemBuilder: (context, index) => Icon(
                      Icons.star,
                      color: Colors.amber,
                    ),
                    itemCount: 5,
                    itemSize: 25.0,
                    direction: Axis.horizontal,
                  ),
                  SizedBox(width: 10),
                  Text(
                    '($raters)',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
          
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              children: [
                if (!_routeStarted)
                  ElevatedButton(
                    onPressed: () => _checkProximityAndStart(startPoint),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF4c6185),
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'Start',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                if (_routeStarted)
                  _isDoneLoading
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: () => _checkProximityAndFinish(endPoint, totalDistance, routeName),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF4c6185),
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            'Done',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ),
                
              ],
            ),
          ),
          if (_currentPosition != null)
                  Positioned(
              bottom: 60,
              left: 20,
              child: ElevatedButton(
                onPressed: () {
                  _moveBackToRoute(startPoint);
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
}
