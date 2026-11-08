"""
Sample indoor map for a single floor (e.g. your CSE-DS department corridor).
This stands in for the "digital database of indoor locations" mentioned in
your abstract. For the PRC demo, this hardcoded graph is enough — in a real
deployment you'd load this from a database per building/floor.

Each node = a physical point (room, junction, landmark).
Each edge = a walkable path between two nodes, with:
    - distance_m: approximate distance in meters (used as edge weight)
    - direction: the instruction to give when walking THIS edge, from the
      perspective of someone standing at the 'from' node facing forward.

OCR_TAG_TO_NODE lets the OCR module confirm the user's location: if the
camera reads a signboard "101", we map it to the room_101 node so we can
correct/confirm position without needing indoor GPS or beacons.
"""

import networkx as nx

def build_location_graph() -> nx.Graph:
    G = nx.Graph()

    nodes = [
        "entrance",
        "reception",
        "junction_1",
        "stairs",
        "room_101",
        "room_102",
        "room_103",
        "washroom",
        "lab_1",
    ]
    G.add_nodes_from(nodes)

    edges = [
        ("entrance",   "reception",   {"distance_m": 8,  "direction": "walk straight for 8 meters"}),
        ("reception",  "junction_1",  {"distance_m": 6,  "direction": "walk straight for 6 meters"}),
        ("junction_1", "stairs",      {"distance_m": 4,  "direction": "turn left and walk 4 meters to the stairs"}),
        ("junction_1", "room_101",    {"distance_m": 5,  "direction": "turn right and walk 5 meters"}),
        ("room_101",   "room_102",    {"distance_m": 3,  "direction": "continue straight for 3 meters"}),
        ("room_102",   "room_103",    {"distance_m": 3,  "direction": "continue straight for 3 meters"}),
        ("junction_1", "washroom",    {"distance_m": 6,  "direction": "turn left and walk 6 meters"}),
        ("stairs",     "lab_1",       {"distance_m": 7,  "direction": "go up the stairs and walk 7 meters"}),
    ]
    for u, v, attrs in edges:
        G.add_edge(u, v, **attrs)

    return G

# Maps digits read by OCR off a signboard to a graph node
OCR_TAG_TO_NODE = {
    "101": "room_101",
    "102": "room_102",
    "103": "room_103",
}

# EXPANDED aliases — covers all the natural ways someone might say each room
# when speaking to the app. Add more rows here if needed.
DESTINATION_ALIASES = {
    # entrance
    "entrance": "entrance",
    "entry": "entrance",
    "main entrance": "entrance",
    "main door": "entrance",
    "front door": "entrance",
    "outside": "entrance",
    "exit": "entrance",

    # reception
    "reception": "reception",
    "front desk": "reception",
    "reception desk": "reception",
    "help desk": "reception",
    "information desk": "reception",
    "office": "reception",

    # stairs
    "stairs": "stairs",
    "staircase": "stairs",
    "stair": "stairs",
    "steps": "stairs",
    "stairway": "stairs",
    "go up": "stairs",

    # washroom
    "washroom": "washroom",
    "restroom": "washroom",
    "toilet": "washroom",
    "bathroom": "washroom",
    "lavatory": "washroom",
    "loo": "washroom",
    "wc": "washroom",
    "wash room": "washroom",
    "rest room": "washroom",

    # lab_1
    "lab": "lab_1",
    "lab one": "lab_1",
    "lab 1": "lab_1",
    "laboratory": "lab_1",
    "computer lab": "lab_1",
    "computer laboratory": "lab_1",
    "coding lab": "lab_1",
    "it lab": "lab_1",

    # room_101
    "room 101": "room_101",
    "room one o one": "room_101",
    "101": "room_101",
    "one o one": "room_101",
    "one zero one": "room_101",
    "room one hundred and one": "room_101",
    "room hundred and one": "room_101",

    # room_102
    "room 102": "room_102",
    "room one o two": "room_102",
    "102": "room_102",
    "one o two": "room_102",
    "one zero two": "room_102",

    # room_103
    "room 103": "room_103",
    "room one o three": "room_103",
    "103": "room_103",
    "one o three": "room_103",
    "one zero three": "room_103",
}