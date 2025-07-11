import 'dart:async'; // Add this import for StreamSubscription
import 'dart:ui'; // Import for BackdropFilter
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Import for Google Maps
import 'package:connectivity_plus/connectivity_plus.dart'; // Import for connectivity
import 'UserStatus_Firebase.dart';
import 'RoutePage.dart';
import 'ViewRouteScreen.dart';
import 'main.dart';
import 'Events.dart';
import 'package:intl/intl.dart';
import 'ViewEvent.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({Key? key}) : super(key: key);

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 1; // Current index for the bottom navigation bar
  StreamSubscription<List<ConnectivityResult>>? _subscription; // Subscription for connectivity changes
  bool _isDialogShowing = false; // Flag to track if the dialog is showing
  List<Event> _events = [];
  bool _isLoading = true;
  late TabController _tabController;

  void _onItemTapped(int index) {
    if (index == _selectedIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/discover');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/community');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  List<Map<String, dynamic>> _publicRoutes = [];
  List<Map<String, dynamic>> _filteredPublicRoutes = []; // To store filtered routes
  TextEditingController _areaController = TextEditingController(); // Controller for area name input

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
    });

    // Fetch all events
    List<Event> events = await context.read<UserState>().getEvents();

    // Get the current time
    final DateTime now = DateTime.now();

    // Find outdated events
    List<Event> outdatedEvents = events.where((event) => event.dateTime.isBefore(now)).toList();

    // Delete outdated events from Firestore
    for (Event event in outdatedEvents) {
      await context.read<UserState>().deleteEvent(event.id);
    }

    // Remove outdated events from the list
    events.removeWhere((event) => event.dateTime.isBefore(now));

    setState(() {
      _events = events;
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchPublicRoutes();
    _listenToConnectivity(); // Start listening to connectivity changes
    _fetchEvents();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchEvents();
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
    _tabController.dispose();
    _subscription?.cancel(); // Cancel the subscription when the widget is disposed
    super.dispose();
  }

  // Method to calculate the distance between two points
  double _calculateDistance(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(start.latitude, start.longitude, end.latitude, end.longitude);
  }

  Future<void> _fetchPublicRoutes() async {
    CollectionReference publicRoutes = FirebaseFirestore.instance.collection('routes');
    QuerySnapshot querySnapshot = await publicRoutes.get();
    List<Map<String, dynamic>> fetchedRoutes = querySnapshot.docs.map((doc) {
      var data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      data['added'] = false; // Initialize added field
      return data;
    }).toList();

    // Get the user's current location
    Position position = await Geolocator.getCurrentPosition();
    LatLng userLocation = LatLng(position.latitude, position.longitude);

    // Calculate the distance for each route
    for (var route in fetchedRoutes) {
      if (route['markers'] != null && route['markers'].isNotEmpty) {
        LatLng routeStart = LatLng(route['markers'][0]['lat'], route['markers'][0]['lng']);
        route['distanceToUser'] = _calculateDistance(userLocation, routeStart);
      } else {
        route['distanceToUser'] = double.infinity; // If no markers, set a large distance
      }
    }

    // Sort routes based on distance to user
    fetchedRoutes.sort((a, b) => a['distanceToUser'].compareTo(b['distanceToUser']));

    setState(() {
      _publicRoutes = fetchedRoutes;
      _filteredPublicRoutes = fetchedRoutes;
    });
  }

  Future<void> _addRouteToMyRoutes(Map<String, dynamic> routeData, int index) async {
    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    if (user != null) {
      CollectionReference userRoutes = FirebaseFirestore.instance.collection('userInfo').doc(user.uid).collection('My Routes');

      // Check if the route already exists in the user's routes
      QuerySnapshot querySnapshot;
      if (routeData.containsKey('routeId')) {
        // New routes with routeId
        querySnapshot = await userRoutes.where('routeId', isEqualTo: routeData['routeId']).get();
      } else {
        // Old routes without routeId
        querySnapshot = await userRoutes.where('markers', isEqualTo: routeData['markers']).get();
      }

      if (querySnapshot.docs.isEmpty) {
        await userRoutes.add(routeData);
        setState(() {
          _filteredPublicRoutes[index]['added'] = true; // Mark the route as added
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${routeData['name']} added to your routes')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${routeData['name']} is already in your routes')));
      }
    }
  }

  void _filterRoutes() {
    String query = _areaController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredPublicRoutes = _publicRoutes;
      } else {
        _filteredPublicRoutes = _publicRoutes.where((route) {
          String routeArea = route['area']?.toLowerCase() ?? '';
          String routeName = route['name']?.toLowerCase() ?? '';
          return routeArea.contains(query) || routeName.contains(query);
        }).toList();
      }
    });
  }



  void _showProfilePictureDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
              Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        return Future.value(false); // Disable back button
      },
      child: Scaffold(
        backgroundColor: Color(0xFFdbe4ee),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Color(0xFF4c6185),
          title: Row(
            children: [
              Consumer<UserState>(
                builder: (context, userState, child) {
                  return GestureDetector(
                    onTap: () => _showProfilePictureDialog(userState.profileImageUrl),
                    child: Row(
                      children: [
                        if (userState.profileImageUrl.isNotEmpty)
                          CircleAvatar(
                            backgroundImage: NetworkImage(userState.profileImageUrl),
                          ),
                        const SizedBox(width: 8),
                        Text(userState.username),
                      ],
                    ),
                  );
                },
              ),
              Spacer(),
              IconButton(
              icon: Icon(Icons.exit_to_app),
              onPressed: () async {
  // Cancel Firestore event listeners before signing out
  await context.read<UserState>().cancelEventListener();

  // Cancel other subscriptions
  _subscription?.cancel();

  // Sign out the user
  await context.read<UserState>().signOutUser();

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Successfully logged out')),
  );

  // Navigate to the main screen and remove all previous routes
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (context) => MyMainScreen()),
    (Route<dynamic> route) => false, // Removes all routes except for MyMainScreen
  );
},
            ),

            ],
          ),
          centerTitle: true,
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Discover Routes'),
              Tab(text: 'Discover Events'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: 10,),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: TextField(
                          controller: _areaController,
                          decoration: InputDecoration(
                            filled: true,
                            hintText: 'Enter area or name to filter routes',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: Color(0xFF4c6185),),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.search),
                              onPressed: _filterRoutes,
                            ),
                          ),
                          onSubmitted: (value) {
                            _filterRoutes();
                          },
                        ),
                      ),
                      SizedBox(height: 5,),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _filteredPublicRoutes.length,
                          itemBuilder: (context, index) {
                            String routeName = _filteredPublicRoutes[index]['name'] ?? 'Route ${index + 1}';
                            String area = _filteredPublicRoutes[index]['area'] ?? 'Unknown area';
                            String distance = 'Distance: ${_filteredPublicRoutes[index]['totalDistance'] != null ? '${_filteredPublicRoutes[index]['totalDistance']} km' : 'Unknown distance'}';

                            return Container(
                              margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    spreadRadius: 2,
                                    blurRadius: 5),
                                ],
                              ),
                              child: ListTile(
                                //contentPadding: EdgeInsets.all(16.0),
                                title: Row(
                                  children: [
                                    //SizedBox(width: 30),
                                    Text(routeName,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontStyle: FontStyle.italic),
                                    ),
                                    ]
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                    children: [
                                      Icon(Icons.place),
                                      SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          area,
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                    ],
                                  ),
                                    Row(
                                      children: [
                                        Icon(Icons.straighten_outlined),
                                        SizedBox(width: 5),
                                        Text(distance),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    _filteredPublicRoutes[index]['added'] ? Icons.where_to_vote : Icons.add_location,
                                  ),
                                  onPressed: () {
                                    if (!_filteredPublicRoutes[index]['added']) {
                                      _addRouteToMyRoutes(_filteredPublicRoutes[index], index);
                                    }
                                  },
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ViewRouteScreen(routeData: _filteredPublicRoutes[index]),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _isLoading
              ? Center(child: CircularProgressIndicator())
              : _events.isEmpty
                  ? Center(child: Text('No Available Events'))
                  : ListView.builder(
                      shrinkWrap: true, // Ensure the ListView doesn't exceed the available space
                      itemCount: _events.length,
                      itemBuilder: (context, index) {
                        Event event = _events[index];
                        String eventName = event.name;
                        String eventArea = event.eventArea.isNotEmpty ? event.eventArea : 'Unknown area';
                        String formattedDateTime = '${DateFormat('yyyy-MM-dd – kk:mm').format(event.dateTime)}';

                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                spreadRadius: 2,
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: ListTile(
                            title: Text(
                              eventName,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontStyle: FontStyle.italic),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                               Row(
                                    children: [
                                      Icon(Icons.place),
                                      SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          eventArea,
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                    ],
                                  ),
                                SizedBox(height: 5),
                                Row(
                                  children: [ 
                                  Icon(Icons.event),
                                  SizedBox(width: 5),
                                  Text(formattedDateTime),
                                  ]
                                ),
                              ],
                            ),
                            onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ViewEventScreen(eventId: event.id), // Pass the event ID here
                                  ),
                                );
                              },
                          ),
                        );
                      },
                    ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Color(0xFF4c6185),
          type: BottomNavigationBarType.fixed, // Ensures fixed style
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_outline),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_run),
              label: 'Discover',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups), 
              label: 'Community'
              ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_circle),
              label: 'Profile',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Color.fromARGB(255, 0, 132, 241),
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}
