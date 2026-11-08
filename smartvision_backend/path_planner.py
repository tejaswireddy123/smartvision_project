"""
Path planning module.

Implements the "graph-based path-planning algorithm" mentioned in your
abstract using Dijkstra's shortest path (via networkx), weighted by
distance_m on each edge. Converts the resulting node sequence into
plain-English turn-by-turn instructions for the voice module.
"""

import networkx as nx
from locations_data import build_location_graph, DESTINATION_ALIASES

_graph = build_location_graph()


def resolve_destination(spoken_text: str) -> str | None:
    """
    Loosely match free-form speech/text ('take me to room 101', 'washroom
    please') against known destination names. Returns a node id or None.

    Three-pass matching so the user doesn't have to say the exact alias:
      1. Exact substring match (alias appears inside spoken text)
      2. Partial word match (every word in alias appears in spoken text)
      3. Single-word overlap (any important word matches)
    """
    text = spoken_text.lower().strip()

    # Remove common filler words so "please take me to the lab" still matches
    for filler in ("please", "take me to", "navigate to", "go to", "i want to go to",
                   "bring me to", "where is", "find", "the", "a", "an"):
        text = text.replace(filler, " ")
    text = " ".join(text.split())  # collapse whitespace

    # Pass 1: exact substring — alias is fully contained in what was said
    for alias, node in DESTINATION_ALIASES.items():
        if alias in text:
            return node

    # Pass 2: every word in the alias is present in the spoken text
    spoken_words = set(text.split())
    for alias, node in DESTINATION_ALIASES.items():
        alias_words = set(alias.split())
        if alias_words and alias_words.issubset(spoken_words):
            return node

    # Pass 3: single important keyword overlap (catches "lab", "stairs", etc.)
    skip_words = {"room", "go", "to", "the", "a", "and", "or", "in", "at"}
    for alias, node in DESTINATION_ALIASES.items():
        for word in alias.split():
            if word not in skip_words and word in spoken_words:
                return node

    return None


def plan_route(start_node: str, destination_node: str) -> list[str]:
    """
    Returns the sequence of node ids from start to destination using
    Dijkstra's algorithm (shortest path by cumulative distance_m).
    Raises networkx.NetworkXNoPath if no route exists.
    """
    return nx.dijkstra_path(_graph, start_node, destination_node, weight="distance_m")


def route_to_instructions(path: list[str]) -> list[str]:
    """
    Converts a node path into a list of spoken instructions, one per
    edge, plus a final "you have arrived" message.
    """
    instructions = []
    for i in range(len(path) - 1):
        edge_data = _graph.edges[path[i], path[i + 1]]
        instructions.append(edge_data["direction"])
    instructions.append(f"You have arrived at {path[-1].replace('_', ' ')}.")
    return instructions


def total_distance(path: list[str]) -> float:
    return sum(
        _graph.edges[path[i], path[i + 1]]["distance_m"]
        for i in range(len(path) - 1)
    )


if __name__ == "__main__":
    # Quick test — run:  python path_planner.py
    test_phrases = [
        "take me to room 101",
        "lab",
        "computer lab",
        "washroom please",
        "go to stairs",
        "navigate to reception",
        "bathroom",
        "go to lab one",
        "room one o one",
    ]
    for phrase in test_phrases:
        dest = resolve_destination(phrase)
        print(f"'{phrase}'  →  {dest}")