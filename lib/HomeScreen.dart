import 'dart:ui'; // Import for BackdropFilter
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Import for Google Maps
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Import for connectivity
import 'dart:async'; // Import for StreamSubscription
import 'main.dart';
import 'RoutePage.dart';
import 'UserStatus_Firebase.dart';
import 'ViewRouteScreen.dart';
import 'Events.dart';
import 'package:intl/intl.dart'; // Import for DateFormat'
import 'ViewEvent.dart';
import 'viewEvenForOutdated.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0; // Current index for the bottom navigation bar
  late StreamSubscription<List<ConnectivityResult>> _subscription; // Subscription for connectivity changes
  bool _isDialogShowing = false; // Flag to track if the dialog is showing
  
  late TabController _tabController;

  // Initial position of the FloatingActionButton
  double _xPosition = 0.9; // Initial horizontal position (1.0 is the far right, 0.0 is the far left)
  double _yPosition = 0.95; // Initial vertical position (1.0 is the bottom, 0.0 is the top)

  List<dynamic> _routes = [];
  List<dynamic> _filteredRoutes = []; // To store filtered routes
  TextEditingController _areaController = TextEditingController(); // Controller for area name input
  bool _showOutdatedEvents = false; // To toggle outdated events visibility
  bool _showUpcomingEvents = true; // To toggle upcoming events visibility


  @override
  void initState() {
  super.initState();
  _tabController = TabController(length: 2, vsync: this);
  _requestLocationPermission();
  _listenToConnectivity();
  _listenToEvents(); // Start listening to real-time updates for events
}

void _listenToEvents() {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? user = _auth.currentUser;
  if (user != null) {
    FirebaseFirestore.instance
        .collection('userInfo')
        .doc(user.uid)
        .collection('My Events')
        .snapshots()
        .listen((snapshot) {
      List<Event> events = snapshot.docs.map((doc) {
        return Event.fromFirestore(doc);
      }).toList();

      if (mounted) {
        setState(() {
          context.read<UserState>().updateMyEvents(events);
        });
      }
    });
  }
}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handleEventDeletion();
  }

  void _handleEventDeletion() {
    final result = ModalRoute.of(context)?.settings.arguments as bool?;
    if (result == true) {
      context.read<UserState>().fetchMyEvents();
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
    _tabController.dispose();
    _subscription.cancel(); // Cancel the subscription when the widget is disposed
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isDenied || status.isRestricted) {
      await Permission.location.request();
    }
    if (await Permission.location.isGranted) {
      _fetchRoutes();
    }
  }

  double _calculateDistance(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(start.latitude, start.longitude, end.latitude, end.longitude);
  }

  Future<void> _fetchRoutes() async {
    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    if (user != null) {
      CollectionReference userRoutes = FirebaseFirestore.instance.collection('userInfo').doc(user.uid).collection('My Routes');
      QuerySnapshot querySnapshot = await userRoutes.get();
      List<dynamic> fetchedRoutes = querySnapshot.docs.map((doc) => {
        ...doc.data() as Map<String, dynamic>,
        'id': doc.id // Store document ID for deletion
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

      if (!mounted) return;

      setState(() {
        _routes = fetchedRoutes;
        _filteredRoutes = fetchedRoutes;
      });
    }
  }

  Future<void> _deleteRoute(int index) async {
    final FirebaseAuth _auth = FirebaseAuth.instance;
    User? user = _auth.currentUser;
    if (user != null) {
      String routeId = _filteredRoutes[index]['id'];
      CollectionReference userRoutes = FirebaseFirestore.instance.collection('userInfo').doc(user.uid).collection('My Routes');
      await userRoutes.doc(routeId).delete();
      
      if (!mounted) return;

      setState(() {
        _filteredRoutes.removeAt(index);
        _routes.removeWhere((route) => route['id'] == routeId); // Also remove from _routes
      });
    }
  }

  void _filterRoutes() {
    String query = _areaController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredRoutes = _routes;
      } else {
        _filteredRoutes = _routes.where((route) {
          String routeArea = route['area']?.toLowerCase() ?? '';
          String routeName = route['name']?.toLowerCase() ?? '';
          return routeArea.contains(query) || routeName.contains(query);
        }).toList();
      }
    });
  }

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
              Tab(text: 'My Routes'),
              Tab(text: 'My Events'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            //My Routes Tap :
            Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10,),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: TextField(
                          controller: _areaController,
                          decoration: InputDecoration(
                            hintText: 'Enter area or name to filter routes',
                            filled: true,
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
                      const SizedBox(height: 5,),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _filteredRoutes.length,
                          itemBuilder: (context, index) {
                            String routeName = _filteredRoutes[index]['name'] ?? 'Route ${index + 1}';
                            String area = _filteredRoutes[index]['area'] ?? 'Unknown area';
                            String distance = 'Route Distance: ${_filteredRoutes[index]['totalDistance'] != null ? '${_filteredRoutes[index]['totalDistance']} km' : 'Unknown distance'}';

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
                                title: Text(
                                  routeName,
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
                                  icon: Icon(Icons.delete, color: const Color.fromARGB(255, 0, 0, 0)),
                                  onPressed: () async {
                                    bool? confirmDelete = await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: Text('Remove Route'),
                                          content: Text('Are you sure you want to remove $routeName from your routes?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.of(context).pop(false);
                                              },
                                              child: Text('No'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.of(context).pop(true);
                                              },
                                              child: Text('Yes'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (confirmDelete == true) {
                                      await _deleteRoute(index);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$routeName successfully removed')),
                                      );
                                    }
                                  },
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ViewRouteScreen(routeData: _filteredRoutes[index]),
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
                        Align(
                  alignment: FractionalOffset(_xPosition, _yPosition),
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _xPosition += details.delta.dx / MediaQuery.of(context).size.width;
                        _yPosition += details.delta.dy / MediaQuery.of(context).size.height;
                      });
                    },
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MapScreen()),
                      ).then((_) => _fetchRoutes()); // Refresh routes after coming back from MapScreen
                    },
                    child: FloatingActionButton(
                      onPressed: null,
                      heroTag: 'addRoute', // Unique hero tag
                      shape: const CircleBorder(),
                      backgroundColor: Color.fromARGB(255, 80, 132, 221),
                      child: Icon(
                        Icons.add,
                        size: 40,
                        color: Color(0xFFdbe4ee),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // My Events implementation
            Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // My Events Tab in HomeScreen
                    Expanded(
                      child: Consumer<UserState>(
                        builder: (context, userState, child) {
                          if (userState.myEvents.isEmpty) {
                            return Center(child: Text('No events found.'));
                          }

                          final DateTime now = DateTime.now();
                          List<Event> upcomingEvents = userState.myEvents.where((event) => event.dateTime.isAfter(now)).toList();
                          List<Event> outdatedEvents = userState.myEvents.where((event) => event.dateTime.isBefore(now)).toList();

                          // Sort events
                          upcomingEvents.sort((a, b) => a.dateTime.compareTo(b.dateTime));
                          outdatedEvents.sort((a, b) => b.dateTime.compareTo(a.dateTime));

                          return ListView(
                            children: [
                              // Upcoming events dropdown
                              ListTile(
                                title: Text('Upcoming Events'),
                                trailing: Icon(
                                  _showUpcomingEvents
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                ),
                                onTap: () {
                                  setState(() {
                                    _showUpcomingEvents = !_showUpcomingEvents;
                                  });
                                },
                              ),
                              // Upcoming events
                              if (_showUpcomingEvents)
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: upcomingEvents.length,
                                  itemBuilder: (context, index) {
                                    Event event = upcomingEvents[index];
                                    return _buildEventTile(event);
                                  },
                                ),
                              // Divider for outdated events
                              ListTile(
                                title: Text('Outdated Events'),
                                trailing: Icon(
                                  _showOutdatedEvents
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                ),
                                onTap: () {
                                  setState(() {
                                    _showOutdatedEvents = !_showOutdatedEvents;
                                  });
                                },
                              ),
                              // Outdated events
                              if (_showOutdatedEvents)
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: outdatedEvents.length,
                                  itemBuilder: (context, index) {
                                    Event event = outdatedEvents[index];
                                    return _buildEventTile(event);
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter, // Adjust this to change the position
                      child: Padding(
                        padding: const EdgeInsets.all(20.0), // Adjust padding as needed
                        child: SizedBox(
                          width: 240,  // Adjust the width of the button as needed
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color.fromARGB(255, 80, 132, 221),  // Change the button color
                              foregroundColor: Colors.white,       // Change the text/icon color
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 16),  // Adjust padding
                            ),
                            icon: Icon(Icons.groups, size: 22),  // Add a suffix icon (e.g., "add" icon)
                            label: Text(
                              'Create New Running Event',
                              style: TextStyle(fontSize: 18),
                            ),
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => CreateEventScreen()),
                              );

                              // If a new event was created, refresh the events list
                              if (result == true) {
                                await context.read<UserState>().fetchMyEvents();
                              }
                            },
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ],
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

  Widget _buildEventTile(Event event) {
  String eventArea = event.eventArea.isNotEmpty ? event.eventArea : 'Unknown area';
  String formattedDateTime = DateFormat('yyyy-MM-dd – kk:mm').format(event.dateTime);

  // Check if the event is outdated
  bool isOutdated = event.dateTime.isBefore(DateTime.now());

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
        event.name,
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
                  overflow: TextOverflow.ellipsis,
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
            ],
          ),
        ],
      ),
      onTap: () {
        // Navigate to different screens based on whether the event is outdated
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => isOutdated
                ? ViewEvent2Screen(eventId: event.id) // Navigate to ViewEvent2Screen if outdated
                : ViewEventScreen(eventId: event.id), // Navigate to ViewEventScreen otherwise
          ),
        );
      },
    ),
  );
}

}
