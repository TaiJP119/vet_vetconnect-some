import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Your Google API Key here:
const String googleApiKey = 'YOUR-API-KEY';

class Place {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final bool is24hrs;
  final bool openNow;
  final double rating;

  String? contact;
  String? openingHours;
  String? eta;
  String? distance;

  Place({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.is24hrs = false,
    this.openNow = false,
    this.rating = 0.0,
    this.contact,
    this.openingHours,
    this.eta,
    this.distance,
  });

  factory Place.fromGoogle(Map<String, dynamic> json, {bool is24hr = false}) {
    final openNow = (json['opening_hours']?['open_now'] ?? false) as bool;
    final rating = (json['rating'] ?? 0.0).toDouble();
    return Place(
      placeId: json['place_id'],
      name: json['name'],
      address: json['formatted_address'] ?? '',
      lat: json['geometry']['location']['lat'],
      lng: json['geometry']['location']['lng'],
      is24hrs: is24hr,
      openNow: openNow,
      rating: rating,
    );
  }
}

class VetFinderPage extends StatefulWidget {
  @override
  _VetFinderPageState createState() => _VetFinderPageState();
}

class _VetFinderPageState extends State<VetFinderPage> {
  final Completer<GoogleMapController> _mapController = Completer();
  Position? _currentPosition;
  List<Place> _places = [];
  Set<Marker> _markers = {};
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    LocationPermission permission;
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
      });
      _moveMap(position.latitude, position.longitude);
    }
  }

  Future<void> _moveMap(double lat, double lng) async {
    final controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
  }

  Future<void> _searchPlaces(String query) async {
    if (_currentPosition == null) return;
    setState(() {
      _isLoading = true;
      _places.clear();
      _markers.clear();
    });
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(query)}'
      '&location=${_currentPosition!.latitude},${_currentPosition!.longitude}'
      '&radius=5000'
      '&key=$googleApiKey',
    );
    final response = await http.get(url);
    print('API URL: $url');
    print('API response: ${response.body}'); // <--- add this
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      if (body['status'] != 'OK') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'API error: ${body['status']} ${body['error_message'] ?? ''}')),
        );
      }
      List<Place> foundPlaces = [];
      for (final result in body['results']) {
        foundPlaces.add(Place.fromGoogle(result));
      }
      await _enrichWithDetailsAndEta(foundPlaces);
      setState(() {
        _places = _sortedPlaces(foundPlaces);
        _addMarkers();
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed.')),
      );
    }
  }

  Future<void> _find24hrEmergencyVet() async {
    if (_currentPosition == null) return;
    setState(() {
      _isLoading = true;
      _places.clear();
      _markers.clear();
    });
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent("24 hour emergency vet")}'
      '&location=${_currentPosition!.latitude},${_currentPosition!.longitude}'
      '&radius=10000'
      '&key=$googleApiKey',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      List<Place> foundPlaces = [];
      for (final result in body['results']) {
        foundPlaces.add(Place.fromGoogle(result, is24hr: true));
      }
      await _enrichWithDetailsAndEta(foundPlaces, mustBe24hr: true);
      setState(() {
        _places = _sortedPlaces(foundPlaces);
        _addMarkers();
        _isLoading = false;
      });
      if (_places.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No true 24hr emergency vets found nearby.')),
        );
      }
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to find emergency vet.')),
      );
    }
  }

  Future<void> _enrichWithDetailsAndEta(List<Place> places,
      {bool mustBe24hr = false}) async {
    try {
      if (_currentPosition == null) return;

      // For safe removal while iterating, collect closed places
      final toRemove = <Place>[];
      await Future.wait(places.map((place) async {
        final detailsUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=${place.placeId}&fields=formatted_phone_number,opening_hours&key=$googleApiKey',
        );
        final detailsResponse = await http.get(detailsUrl);
        if (detailsResponse.statusCode == 200) {
          final detailsJson = json.decode(detailsResponse.body);
          final details = detailsJson['result'];
          if (details != null && details is Map<String, dynamic>) {
            if (details.containsKey('formatted_phone_number')) {
              place.contact = details['formatted_phone_number'];
            }
            if (details['opening_hours'] is Map &&
                (details['opening_hours']['weekday_text'] is List)) {
              place.openingHours =
                  (details['opening_hours']['weekday_text'] as List).join(', ');
              if (mustBe24hr) {
                final weekdays =
                    (details['opening_hours']['weekday_text'] as List)
                        .cast<String>();
                final all24hr =
                    weekdays.every((d) => d.contains("Open 24 hours"));
                if (!all24hr) {
                  toRemove.add(place);
                }
              }
            } else if (mustBe24hr) {
              toRemove.add(place);
            }
          } else if (mustBe24hr) {
            toRemove.add(place);
          }
        } else if (mustBe24hr) {
          toRemove.add(place);
        }

        // Directions API for ETA/distance
        final dirUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
          '&destination=${place.lat},${place.lng}'
          '&mode=driving'
          '&key=$googleApiKey',
        );
        final dirResponse = await http.get(dirUrl);
        if (dirResponse.statusCode == 200) {
          final routes = json.decode(dirResponse.body)['routes'];
          if (routes != null &&
              routes.isNotEmpty &&
              routes[0]['legs'] != null &&
              routes[0]['legs'].isNotEmpty) {
            final leg = routes[0]['legs'][0];
            place.distance = leg['distance']['text'];
            place.eta = leg['duration']['text'];
          }
        }
      }));

      // Remove non-24hr places for 24hr vet search
      if (mustBe24hr) {
        places.removeWhere((p) => toRemove.contains(p));
      }
    } catch (e, stack) {
      print("Error in _enrichWithDetailsAndEta: $e");
      print(stack);
      // Optionally, set _isLoading = false and call setState
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Sort: open, then ETA, then distance, then rating (desc)
  List<Place> _sortedPlaces(List<Place> places) {
    List<Place> sorted = List.from(places);
    sorted.sort((a, b) {
      // Open now first
      if (a.openNow != b.openNow) return b.openNow ? 1 : -1;
      // Shortest ETA
      int etaA = _parseEta(a.eta);
      int etaB = _parseEta(b.eta);
      if (etaA != etaB) return etaA.compareTo(etaB);
      // Shortest distance
      double distA = _parseDistance(a.distance);
      double distB = _parseDistance(b.distance);
      if (distA != distB) return distA.compareTo(distB);
      // Higher review rating
      return b.rating.compareTo(a.rating);
    });
    return sorted;
  }

  int _parseEta(String? eta) {
    // "12 min", "1 hour 2 mins", etc.
    if (eta == null) return 99999;
    int minutes = 0;
    final regHour = RegExp(r'(\d+)\s*hour');
    final regMin = RegExp(r'(\d+)\s*min');
    final matchHour = regHour.firstMatch(eta);
    final matchMin = regMin.firstMatch(eta);
    if (matchHour != null) minutes += int.parse(matchHour.group(1)!) * 60;
    if (matchMin != null) minutes += int.parse(matchMin.group(1)!);
    return minutes > 0 ? minutes : 99999;
  }

  double _parseDistance(String? distance) {
    // "2.4 km" or "950 m"
    if (distance == null) return 99999;
    if (distance.contains('km')) {
      return double.tryParse(distance.split(' ')[0]) ?? 99999;
    } else if (distance.contains('m')) {
      return (double.tryParse(distance.split(' ')[0]) ?? 99999) / 1000.0;
    }
    return 99999;
  }

  void _addMarkers() {
    final Set<Marker> newMarkers = {};
    if (_currentPosition != null) {
      newMarkers.add(
        Marker(
          markerId: MarkerId('user_location'),
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          infoWindow: InfoWindow(title: 'You are here'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    for (final place in _places) {
      newMarkers.add(
        Marker(
          markerId: MarkerId(place.placeId),
          position: LatLng(place.lat, place.lng),
          infoWindow: InfoWindow(title: place.name, snippet: place.address),
        ),
      );
    }
    setState(() {
      _markers = newMarkers;
    });
  }

  Future<void> _openGoogleMaps(Place place) async {
    final googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(place.name)}@${place.lat},${place.lng}');
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl);
    }
  }

  Future<void> _callPhone(String? contact) async {
    if (contact == null) return;
    final telUrl = Uri.parse('tel:$contact');
    if (await canLaunchUrl(telUrl)) {
      await launchUrl(telUrl);
    }
  }

  Widget _buildExpansionTile(Place place) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: ExpansionTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              place.is24hrs ? Icons.local_hospital : Icons.place,
              color: place.is24hrs ? Colors.red : Colors.teal,
              size: 30,
            ),
            SizedBox(height: 2),
            Container(
              decoration: BoxDecoration(
                color: place.openNow ? Colors.green : Colors.grey,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                place.openNow ? 'Open' : 'Closed',
                style: TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
          ],
        ),
        title: Text(
          place.name,
          style: TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Row(
            children: [
              Icon(Icons.directions_car, size: 14, color: Colors.grey),
              SizedBox(width: 3),
              Text('${place.eta ?? "-"}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              SizedBox(width: 10),
              Icon(Icons.social_distance, size: 14, color: Colors.grey),
              SizedBox(width: 3),
              Text('${place.distance ?? "-"}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              SizedBox(width: 10),
              Icon(Icons.star, size: 14, color: Colors.orange[600]),
              Text(
                place.rating > 0 ? '${place.rating.toStringAsFixed(1)}' : '-',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (place.address.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.teal, size: 16),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place.address,
                          style: TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                ],
                if (place.contact != null) ...[
                  GestureDetector(
                    onTap: () => _callPhone(place.contact),
                    child: Row(
                      children: [
                        Icon(Icons.phone, size: 16, color: Colors.blue),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            place.contact!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 6),
                ],
                if (place.openingHours != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.access_time,
                          size: 16, color: Colors.teal[400]),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place.openingHours!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: place.contact != null
                          ? () => _callPhone(place.contact)
                          : null,
                      icon: Icon(Icons.phone),
                      label: Text("Call"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          minimumSize: Size(80, 32),
                          textStyle: TextStyle(fontSize: 13)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openGoogleMaps(place),
                      icon: Icon(Icons.map),
                      label: Text("Open Map"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          minimumSize: Size(110, 32),
                          textStyle: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Find Vets Nearby'),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
            icon: Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
            tooltip: "Locate Me",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search any place (e.g. "vet", "pet hospital")',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      prefixIcon: Icon(Icons.search),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                    ),
                    onSubmitted: (value) {
                      _searchPlaces(value);
                    },
                  ),
                ),
                SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: _find24hrEmergencyVet,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(horizontal: 10)),
                  icon: Icon(Icons.local_hospital, size: 20),
                  label: Text('24hr Vet'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _currentPosition == null
                ? Center(child: CircularProgressIndicator())
                : GoogleMap(
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    initialCameraPosition: CameraPosition(
                      target: _currentPosition != null
                          ? LatLng(_currentPosition!.latitude,
                              _currentPosition!.longitude)
                          : LatLng(0, 0),
                      zoom: 14,
                    ),
                    markers: _markers,
                    onMapCreated: (controller) {
                      if (!_mapController.isCompleted)
                        _mapController.complete(controller);
                    },
                  ),
          ),
          Expanded(
            flex: 3,
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _places.isEmpty
                    ? Center(
                        child: Text(
                        'No places found.\nTry searching above!',
                        textAlign: TextAlign.center,
                      ))
                    : ListView.builder(
                        itemCount: _places.length,
                        itemBuilder: (ctx, i) =>
                            _buildExpansionTile(_places[i]),
                      ),
          ),
        ],
      ),
    );
  }
}
