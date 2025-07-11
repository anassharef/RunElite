import 'dart:ui'; // Import for BackdropFilter
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Import for connectivity
import 'dart:async'; // Import for StreamSubscription
import 'UserStatus_Firebase.dart';
import 'main.dart';

class CommunityScreen extends StatefulWidget {
  @override
  _CommunityScreenState createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  int _selectedIndex = 2; // Current index for the bottom navigation bar
  final TextEditingController _searchController = TextEditingController();
  late StreamSubscription<List<ConnectivityResult>> _subscription; // Connectivity subscription
  bool _isDialogShowing = false; // Flag to track if the dialog is showing

  @override
  void initState() {
    super.initState();
    _listenToConnectivity(); // Listen to connectivity changes
  }

  void _listenToConnectivity() {
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      if (result.first == ConnectivityResult.none) {
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
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop(); // Close the dialog when tapped
              },
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 150,
                  backgroundImage: NetworkImage(imageUrl),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
              ),
            ),
          ],
        ),
      );
    },
  );
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
        ),
      body: FutureBuilder(
        future: Future.wait([
          context.read<UserState>().fetchGlobalStatistics(),
          context.read<UserState>().fetchTopUsers(),
        ]),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data == null) {
            return Center(child: Text('No data available'));
          } else {
            final globalStats = snapshot.data![0] as Map<String, double>;
            final topUsers = snapshot.data![1] as List<Map<String, dynamic>>;

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 5),
                    // Container for the Community page title
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Community',
                                style: TextStyle(
                                  fontSize: 29,
                                  fontWeight: FontWeight.bold,
                                  color: Color.fromARGB(218, 33, 41, 57),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              SizedBox(width: 10),
                              Icon(
                                Icons.public,
                                color: Color.fromARGB(255, 0, 94, 255),
                                size: 30,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 0)),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Welcome to the Community page! Here you can view the global statistics and the top users in the community.',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color.fromARGB(210, 38, 76, 142),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    // Container for the Top Users section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Text(
                                'Top Users',
                                style: TextStyle(
                                  fontSize: 29,
                                  fontWeight: FontWeight.bold,
                                  color: Color.fromARGB(218, 33, 41, 57),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              SizedBox(width: 10),
                              Icon(
                                Icons.emoji_events_outlined,
                                color: Color.fromARGB(255, 0, 94, 255),
                                size: 30,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 0)),
                                ],
                              ),
                              SizedBox(width: 30),
                              Flexible(
                              child: ElevatedButton(
                                onPressed: () => _navigateToSearchScreen(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color.fromARGB(255, 80, 132, 221),
                                  foregroundColor: const Color.fromARGB(216, 255, 255, 255),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0), // Add some padding for better appearance
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    children: [
                                      Icon(Icons.search),
                                      SizedBox(width: 5),
                                      Text(
                                        'Find Users  ',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            ],
                          ),
                          SizedBox(height: 20),
                          if (topUsers.isNotEmpty) _buildOtherUserRow('First Place:', topUsers[0], true),
                          if (topUsers.length > 1) ...[
                            SizedBox(height: 20),
                            _buildOtherUserRow('Second Place:', topUsers[1], false),
                          ],
                          if (topUsers.length > 2) ...[
                            SizedBox(height: 20),
                            _buildOtherUserRow('Third Place:', topUsers[2], false),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    //Container for the Global Statistics section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Text(
                                'Global Statistics',
                                style: TextStyle(
                                  fontSize: 29,
                                  fontWeight: FontWeight.bold,
                                  color: Color.fromARGB(218, 33, 41, 57),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              SizedBox(width: 10),
                              Icon(
                                FontAwesomeIcons.chartBar,
                                color: Color.fromARGB(255, 0, 94, 255),
                                size: 30,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 0)),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Here is the total statistics for all the community. Don`t hesitate to contribute to it !',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color.fromARGB(210, 38, 76, 142),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          SizedBox(height: 10),
                          Container(
                          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                          decoration: BoxDecoration(
                            color: Color.fromARGB(209, 215, 223, 231),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              SizedBox(height: 5),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(Icons.straighten, size: 20, color: Colors.black),
                                  SizedBox(width: 5),
                                  Text(
                                    'Total Distance :',
                                    style: TextStyle(
                                      fontSize: 16 ,
                                      color: Color.fromARGB(218, 33, 41, 57),
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    '${globalStats['totalDistance']?.toStringAsFixed(2)}' ?? '0.0',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 5),
                                  Text('km', style: TextStyle(fontSize: 18, color: Color.fromARGB(175, 0, 0, 0))),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(FontAwesomeIcons.fire, size: 20, color: Color.fromARGB(161, 255, 0, 0)),
                                  SizedBox(width: 5),
                                  Text(
                                    'Total Calories Burned: ',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Color.fromARGB(218, 33, 41, 57),
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    '${globalStats['totalCalories']?.toStringAsFixed(2)}' ?? '0.0',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 5),
                                  Text('cal', style: TextStyle(fontSize: 18, color: Color.fromARGB(175, 0, 0, 0))),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(FontAwesomeIcons.running, size: 20, color: Color.fromARGB(255, 0, 132, 241)),
                                  SizedBox(width: 5),
                                  Text(
                                    'Total Steps Taken: ',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Color.fromARGB(218, 33, 41, 57),
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    '${globalStats['totalSteps']?.toStringAsFixed(0)}' ?? '0',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 5),
                                  Text('steps', style: TextStyle(fontSize: 18, color: Color.fromARGB(175, 0, 0, 0))),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        },
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
            label: 'Community',
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

Widget _buildOtherUserRow(String place, Map<String, dynamic>? user, bool isFirst) {
  if (user == null) {
    return SizedBox.shrink(); // Return an empty widget if there is no user
  }

  return Container(
    padding: EdgeInsets.all(10),
    margin: EdgeInsets.symmetric(vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.5),
          spreadRadius: 2,
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (isFirst) ...[
              Icon(
                Icons.emoji_events_outlined,
                color: Color.fromARGB(255, 255, 215, 0),
                size: isFirst ? 30 : 25, // Different icon size for first place
              ),
            ] else
              Icon(
                FontAwesomeIcons.medal,
                color: place == 'Second Place:' ? Color.fromARGB(158, 166, 175, 184) : Color.fromARGB(175, 205, 127, 50),
                size: isFirst ? 30 : 25, // Different icon size for other places
              ),
            SizedBox(width: 5),
            Text(
              '$place ',
              style: TextStyle(
                fontSize: isFirst ? 18 : 16, // Different font size for first place
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(218, 33, 41, 57),
              ),
            ),
            SizedBox(width: 30),
            CircleAvatar(
              backgroundImage: NetworkImage(user['profileImageUrl']),
              radius: isFirst ? 30 : 25, // Different avatar size for first place,
            ),
            SizedBox(width: 20),
            Expanded(
              child: Text(
                user['username'] ?? 'Anonymous',
                style: TextStyle(fontSize: isFirst ? 18 : 16, fontWeight: FontWeight.w500),
                overflow: TextOverflow.visible, // Handle overflow with ellipsis
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
          decoration: BoxDecoration(
            color: Color.fromARGB(209, 215, 223, 231),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.straighten, size: isFirst ? 20 : 18, color: Colors.black),
                  SizedBox(width: 5),
                  Text(
                    'Total Distance Walked: ',
                    style: TextStyle(
                      fontSize: isFirst ? 16 : 14,
                      color: Color.fromARGB(218, 33, 41, 57),
                    ),
                  ),
                  SizedBox(width: 20),
                  Text(
                    user['totalDistance']?.toStringAsFixed(2) ?? '0.0',
                    style: TextStyle(
                      fontSize: isFirst ? 18 : 16,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 5),
                  Text('km', style: TextStyle(fontSize: isFirst ? 18 : 16, color: Color.fromARGB(175, 0, 0, 0))),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(FontAwesomeIcons.fire, size: isFirst ? 20 : 18, color: Color.fromARGB(161, 255, 0, 0)),
                  SizedBox(width: 5),
                  Text(
                    'Total Calories Burned: ',
                    style: TextStyle(
                      fontSize: isFirst ? 16 : 14,
                      color: Color.fromARGB(218, 33, 41, 57),
                    ),
                  ),
                  SizedBox(width: 20),
                  Text(
                    user['totalCalories']?.toStringAsFixed(1) ?? '0.0',
                    style: TextStyle(
                      fontSize: isFirst ? 18 : 16,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 5),
                  Text('cal', style: TextStyle(fontSize: isFirst ? 18 : 16, color: Color.fromARGB(175, 0, 0, 0))),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(FontAwesomeIcons.running, size: isFirst ? 20 : 18, color: Color.fromARGB(255, 0, 132, 241)),
                  SizedBox(width: 5),
                  Text(
                    'Total Steps Taken: ',
                    style: TextStyle(
                      fontSize: isFirst ? 16 : 14,
                      color: Color.fromARGB(218, 33, 41, 57),
                    ),
                  ),
                  SizedBox(width: 20),
                  Text(
                    user['totalSteps']?.toString() ?? '0',
                    style: TextStyle(
                      fontSize: isFirst ? 18 : 16,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 5),
                  Text('steps', style: TextStyle(fontSize: isFirst ? 18 : 16, color: Color.fromARGB(175, 0, 0, 0))),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

}

void _navigateToSearchScreen(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => SearchScreen()),
  );
}

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _listenToConnectivity(); // Listen to connectivity changes
  }

  void _listenToConnectivity() {
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      if (result.first == ConnectivityResult.none) {
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

  void _searchUsers(String query) async {
  if (query.isEmpty) {
    setState(() {
      _searchResults.clear();
    });
    return;
  }

  String searchQuery = query.toLowerCase();

  final users = await FirebaseFirestore.instance
      .collection('userInfo')
      .get(); // Fetch all users or apply some other filtering

  List<DocumentSnapshot> matchingUsers = [];

  for (var user in users.docs) {
    String username = user['username'].toString().toLowerCase();
    if (username.contains(searchQuery)) {
      matchingUsers.add(user);
    }
  }

  setState(() {
    _searchResults = matchingUsers;
  });
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 50,
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search users...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Color(0xFF4c6185), width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: Icon(Icons.search, color: Color(0xFF4c6185)),
          ),
          onChanged: _searchUsers,
        ),
        backgroundColor: Color(0xFF4c6185),
      ),
      backgroundColor: Color(0xFFdbe4ee),
      body: ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final user = _searchResults[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(user['profileImageUrl']),
            ),
            title: Text(user['username']),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OtherUserProfileScreen(userId: user.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


class OtherUserProfileScreen extends StatefulWidget {
  final String userId;

  OtherUserProfileScreen({required this.userId});

  @override
  _OtherUserProfileScreenState createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _listenToConnectivity();
  }

  void _listenToConnectivity() {
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      if (result.contains(ConnectivityResult.none)) {
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

  void _showProfilePictureDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color.fromARGB(0, 255, 255, 255),
          child: Stack(
            alignment: Alignment.center,
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop(); // Close the dialog when tapped
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 150,
                    backgroundImage: NetworkImage(imageUrl),
                  ),
                ),
              ),
              Positioned(
                top: 20,
                right: 20,
                child: IconButton(
                  icon: Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog
                  },
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
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('userInfo').doc(widget.userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text('Loading...')),
            body: Center(child: CircularProgressIndicator()),
            backgroundColor: Color(0xFFdbe4ee),
          );
        }

        var user = snapshot.data!;
        return Scaffold(
          appBar: AppBar(
            title: Text('User Profile'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          backgroundColor: Color(0xFFdbe4ee),
          body: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _showProfilePictureDialog(user['profileImageUrl']),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          spreadRadius: 5,
                          blurRadius: 7,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 80,
                      backgroundImage: user['profileImageUrl'] != null && user['profileImageUrl'].isNotEmpty
                          ? NetworkImage(user['profileImageUrl'])
                          : NetworkImage('https://via.placeholder.com/150'),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(
                      color: Colors.black.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    user['username'] ?? 'Unknown User',
                    style: TextStyle(
                      fontSize: 18,
                      shadows: [
                        Shadow(
                          offset: Offset(1.0, 1.0),
                          blurRadius: 3.0,
                          color: Colors.black.withOpacity(0.5),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      'About Me: ',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: TextFormField(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      labelText: '',
                      labelStyle: TextStyle(color: Colors.black, fontSize: 16),
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
                    ),
                    style: TextStyle(color: Colors.black, fontSize: 16),
                    controller: TextEditingController(
                      text: user['About Me'] ?? '',
                    ),
                    readOnly: true,
                    maxLines: 4,
                  ),
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lives in:',
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(height: 5),
                        Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          child: TextFormField(
                            controller: TextEditingController(text: user['Lives in'] ?? ''),
                            decoration: InputDecoration(
                              labelText: '',
                              labelStyle: TextStyle(color: Colors.black, fontSize: 16),
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
                              suffixIcon: Icon(Icons.location_on),
                            ),
                            cursorColor: Colors.black,
                            maxLines: 1,
                            readOnly: true,
                            style: TextStyle(color: Colors.black, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Distance Walked:',
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(height: 5),
                        Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          child: TextFormField(
                            controller: TextEditingController(text: '${user['Total Distance']?.toStringAsFixed(2) ?? '0.0'} km'),
                            decoration: InputDecoration(
                              labelText: '',
                              labelStyle: TextStyle(color: Colors.black, fontSize: 16),
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
                            readOnly: true,
                            style: TextStyle(color: Colors.black, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Steps Taken:',
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(height: 5),
                        Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          child: TextFormField(
                            controller: TextEditingController(text: '${user['Steps Taken']?.toString() ?? '0'}'),
                            decoration: InputDecoration(
                              labelText: '',
                              labelStyle: TextStyle(color: Colors.black, fontSize: 16),
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
                            readOnly: true,
                            style: TextStyle(color: Colors.black, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calories Burned:',
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(height: 5),
                        Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          child: TextFormField(
                            controller: TextEditingController(text: '${user['Calories Burned']?.toStringAsFixed(1) ?? '0.0'} cal'),
                            decoration: InputDecoration(
                              labelText: '',
                              labelStyle: TextStyle(color: Colors.black, fontSize: 16),
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
                            readOnly: true,
                            style: TextStyle(color: Colors.black, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
