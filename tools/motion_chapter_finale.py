"""Nine final, individually authored exchange studies for Borrowed Motion.

The constructive notation records explicit commands and checks the finished
room against the ordinary model.  An allowance is an achievable witness, not
a proof of optimality or a substitute for human difficulty assessment.
"""
from dataclasses import replace

from generate_motion_levels import (
    Actor, make_level, initial_state, swap, wind, replay, won,
    EAST, SOUTH, WEST, NORTH,
)

P = lambda x, y, motion=0: Actor(0, x, y, motion)
B = lambda x, y, motion=0: Actor(1, x, y, motion)


class Composition:
    def __init__(self, name, hint, actors, paths, lesson, *, slash=(), backslash=(), glass=()):
        rectangles = [(a.x, a.y, a.x, a.y) for a in actors]
        for path in paths:
            for (x1, y1), (x2, y2) in zip(path, path[1:]):
                assert x1 == x2 or y1 == y2
                rectangles.append((min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)))
        self.base = make_level(name, hint, actors, [], [], lesson,
                               rectangles=rectangles, slash=slash,
                               backslash=backslash, glass=glass)
        self.state = initial_state(self.base)
        self.actions = []
        self.nests = []

    def exchange(self, index):
        actor = self.state.actors[index]
        assert actor.active and actor.motion != self.state.pocket, (self.base.name, index, "ineffective exchange")
        self.state = swap(self.base, self.state, index)
        self.actions.append(('swap', index))
        return self

    def step(self, count):
        assert count > 0
        self.state = wind(self.base, self.state, count)
        self.actions.append(('wind', count))
        return self

    def at(self, index, x, y, motion=None):
        actor = self.state.actors[index]
        assert (actor.x, actor.y) == (x, y), (self.base.name, index, actor, (x, y))
        assert motion is None or actor.motion == motion, (self.base.name, index, actor, motion)
        return self

    def finish(self, index, x, y):
        self.at(index, x, y)
        assert self.state.pocket == 0
        assert (x, y) not in self.nests
        self.exchange(index)
        actors = list(self.state.actors)
        actors[index] = replace(actors[index], active=False)
        self.state = replace(self.state, actors=tuple(actors))
        self.nests.append((x, y))
        return self

    def level(self):
        board = list(self.base.board)
        for x, y in self.nests:
            board[y * 18 + x] = 4
        result = replace(self.base, board=tuple(board), solution=tuple(self.actions))
        assert len(result.name) <= 24 and len(result.hint) <= 38
        assert len(self.nests) == sum(a.kind == 0 for a in result.actors)
        assert all((a.x, a.y) not in self.nests for a in result.actors if a.kind == 0)
        final, _ = replay(result)
        assert won(final) and final.actors == self.state.actors and final.pocket == self.state.pocket, result.name
        return result


def finale_levels():
    levels = []

    # 56. Several unfinished journeys share two axes before any delivery.
    s = Composition('THE STAIRCASE OF LOANS', 'TRADE PATHS BEFORE THEY FINISH.',
        [P(1,7,EAST), P(9,7,NORTH), P(1,3), P(7,7), P(11,7), B(16,1)],
        [[(1,7),(3,7),(3,5),(5,5),(5,3),(7,3)],
         [(9,7),(9,5),(11,5),(11,3),(13,3),(13,1)],
         [(1,3),(3,3),(3,1),(6,1)],
         [(7,7),(7,5),(9,5),(9,2)], [(11,7),(14,7),(14,4)]],
        'The opening pair changes axes at four successive plain corners before either can settle. Their arrivals then fund a second pair with two more exchanges of axes. Keep the penultimate vertical loan in the pocket while the fifth pearl reaches its final corner; the bell is needed only after that turn.')
    for ax, ay, bx, by in ((3,7,9,5), (3,5,11,5), (5,5,11,3), (5,3,13,3)):
        s.step(2).at(0,ax,ay).at(1,bx,by).exchange(0).exchange(1).exchange(0)
    s.step(2).finish(0,7,3).exchange(2).finish(1,13,1).exchange(3)
    s.step(2).at(2,3,3).at(3,7,5).exchange(2).exchange(3).exchange(2)
    s.step(2).at(2,3,1).at(3,9,5).exchange(2).exchange(3).exchange(2)
    s.step(3).finish(2,6,1).exchange(4).finish(3,9,2)
    s.step(3).at(4,14,7).exchange(4).exchange(5).step(3).finish(4,14,4)
    levels.append(s.level())

    # 57. Five pearls share one loan and a retiring direction converter.
    s = Composition('FIVE UNFINISHED THOUGHTS', 'PREPARE THE CORNERS BEFORE THE TURN.',
        [P(2,6), P(10,6), P(16,6), P(9,7), P(15,7), B(1,1,EAST)],
        [[(2,6),(7,6),(7,2),(3,2),(3,5)],
         [(10,6),(10,2),(12,2),(12,4)],
         [(16,6),(16,1),(14,1),(14,3)],
         [(9,7),(11,7),(11,4)], [(15,7),(13,7),(13,5)]],
        'One loan must serve horizontal preparation, vertical preparation, horizontal preparation again, and the final vertical deliveries. The mirror-bearing pearl is useful long before it can retire. Plan which corners must be staged before each axis conversion; the five destinations share only one motion.',
        slash=[(7,6),(3,2)], backslash=[(7,2)])
    s.exchange(5).exchange(3).step(2).at(3,11,7).exchange(3)
    s.exchange(4).step(3).at(4,13,7).exchange(4)
    s.exchange(0).step(6).at(0,7,6,NORTH).exchange(0)
    s.exchange(1).step(4).at(1,10,2).exchange(1)
    s.exchange(2).step(5).at(2,16,1).exchange(2)
    s.exchange(0).step(4).at(0,7,2,WEST).exchange(0)
    s.exchange(1).step(3).at(1,12,2).exchange(1)
    s.exchange(2).step(3).at(2,14,1).exchange(2)
    s.exchange(0).step(4).at(0,3,2,SOUTH).exchange(0)
    s.exchange(1).step(2).finish(1,12,4)
    s.exchange(2).step(2).finish(2,14,3)
    s.exchange(3).step(4).finish(3,11,4)
    s.exchange(4).step(2).finish(4,13,5)
    s.exchange(0).step(4).finish(0,3,5)
    levels.append(s.level())

    # 58. An extended opening trade precedes the later full-pocket climb.
    s = Composition('THE POCKET RESERVE', 'KEEP A TURN FOR THE ROAD AHEAD.',
        [P(2,7,EAST), P(9,7,NORTH), P(2,6), P(12,7), B(1,1)],
        [[(2,7),(4,7),(4,5),(6,5),(6,3),(8,3),(8,6),(12,6)],
         [(9,7),(9,5),(11,5),(11,3),(13,3),(13,1)],
         [(2,6),(2,2),(5,2)], [(12,7),(16,7),(16,3)]],
        'Four opening axis trades prepare the first arrival. A newly launched pearl then exchanges axes with the unfinished original traveler. Their staggered routes finally supply both parts of the last journey: carry its future horizontal turn in the pocket during the entire vertical climb.')
    for ax, ay, bx, by in ((4,7,9,5), (4,5,11,5), (6,5,11,3), (6,3,13,3)):
        s.step(2).at(0,ax,ay).at(1,bx,by).exchange(0).exchange(1).exchange(0)
    s.step(2).finish(1,13,1).exchange(0).exchange(3)
    s.step(4).at(0,8,6).at(3,16,7)
    s.exchange(0).exchange(3).exchange(0)
    s.step(5).finish(3,16,3).exchange(2).finish(0,12,6)
    s.step(4).at(2,2,2).exchange(2).exchange(4)
    s.step(4).finish(2,5,2)
    levels.append(s.level())

    # A paused orbit lends its speed until a late carrier returns a gentle turn.
    s = Composition('THE RETURNING CURRENT', 'SAVE A TURN FOR THE WAITING ORBIT.',
        [P(2,1,5), P(12,1,5), P(7,3), P(12,7), P(7,4), B(7,7)],
        [[(1,1),(5,1),(5,3),(1,3),(1,1)],
         [(11,1),(16,1),(16,3),(11,3),(11,1)],
         [(7,3),(9,3),(9,1),(10,1)],
         [(12,7),(12,4),(14,4),(14,1)],
         [(7,4),(10,4),(10,2)]],
        'The glass carrier first softens one orbit, but the other orbit remains unfinished. Borrow its fast vertical loan for a second pair: two axis trades and another glass crossing prepare their staggered deliveries. Those arrivals revive and turn the first glass carrier. Its final vertical loan can at last return to the waiting orbit, which finishes after all its borrowers.',
        slash=[(1,1),(5,3),(11,1),(16,3)],
        backslash=[(5,1),(1,3),(16,1),(11,3)],
        glass=[(8,4),(9,2)])
    s.exchange(0).exchange(4).step(1).at(4,8,4,EAST)
    s.exchange(4).exchange(0).step(1).finish(0,3,1)
    s.exchange(2).exchange(1).exchange(3)
    s.step(2).at(2,9,3).at(3,12,4).exchange(2).exchange(3).exchange(2)
    s.step(2).at(2,9,1).at(3,14,4).exchange(2).exchange(3).exchange(2)
    s.step(1).finish(2,10,1).exchange(4)
    s.step(2).finish(3,14,1).at(4,10,4).exchange(4).exchange(5)
    s.step(2).finish(4,10,2).exchange(1).step(2).finish(1,16,2)
    levels.append(s.level())

    # Fast arrivals hand off to a slow pair, then regain a fast horizontal leg.
    s = Composition('THE FAST RETURN', 'A REBOUND CAN BRING THE NEXT TURN.',
        [P(1,5,5), P(5,7,8), P(11,7), P(16,7), P(10,7), B(1,7)],
        [[(1,5),(3,5),(3,3),(5,3),(5,1)],
         [(5,7),(5,5),(7,5),(7,3),(9,3),(9,1),(15,1)],
         [(11,7),(11,1),(14,1)], [(16,7),(16,4),(12,4)],
         [(10,7),(8,7),(8,5)]],
        'Three fast axis trades precede the first arrival. Its northward loan finds glass while its former partner completes a longer mirror route. The next fast traveler passes through that occupied nest and rebounds, returning westward motion for a new borrower. A final trade mixes fast horizontal and slow vertical motion; the two last rebounds must be included when predicting the staggered landings.',
        slash=[(9,3),(9,1)], glass=[(11,3)])
    for ax, ay, bx, by in ((3,5,5,5), (3,3,7,5), (5,3,7,3)):
        s.step(1).at(0,ax,ay).at(1,bx,by).exchange(0).exchange(1).exchange(0)
    s.step(1).finish(0,5,1).exchange(2)
    s.step(4).finish(1,15,1).at(2,11,1,NORTH).exchange(2).exchange(3)
    s.step(3).finish(2,14,1).exchange(4)
    s.step(1).at(3,16,4).at(4,8,7)
    s.exchange(3).exchange(4).exchange(3)
    s.step(2).finish(3,12,4).exchange(5).step(1).finish(4,8,5)
    levels.append(s.level())

    # The factory is the concluding study; the others lead into the shared
    # advanced candidates integrated below.
    return ([levels[0], levels[3], levels[2], levels[4]]
            + _relay_finales() + _allocation_finales() + [levels[1]])


def _relay_finales():
    p = lambda x, y, motion=0: Actor(0, x, y, motion)
    b = lambda x, y, motion=0: Actor(1, x, y, motion)
    s = lambda actor: ('swap', actor)
    w = lambda steps: ('wind', steps)
    return [
        make_level(
            "THE UNFINISHED THREAD", "PAUSE ONE JOURNEY TO WEAVE ANOTHER.",
            [p(1, 7, EAST), p(8, 7, NORTH), p(12, 7), p(6, 7), p(1, 1), b(16, 1)],
            [(3, 4), (11, 3), (16, 5), (8, 6), (6, 2)],
            [w(2), s(0), s(1), s(0), w(1), s(0), s(1), s(2),
             w(2), s(1), s(2), s(1), w(2), s(1), s(2), s(0),
             w(2), s(0), s(3), s(2), s(4), w(2), s(3), s(4), s(3),
             w(2), s(3), s(4), s(3), w(1), s(3), s(5), w(2), s(4)],
            "Pause the first pearl partway through its unfinished vertical leg and lend that axis to a new pair. Their exchange creates a horizontal arrival; it turns the other traveler and releases north to revive the original pearl. Those later arrivals fund the final pair, which must trade axes twice before making staggered landings. The paused pearl is a future delivery, not a spare bell to abandon.",
            rectangles=[(1, 7, 3, 7), (3, 4, 3, 7), (8, 5, 8, 7),
                        (8, 5, 9, 5), (9, 3, 9, 5), (9, 3, 11, 3),
                        (12, 7, 14, 7), (14, 5, 14, 7), (14, 5, 16, 5),
                        (6, 5, 6, 7), (6, 5, 8, 5), (1, 1, 3, 1),
                        (3, 1, 3, 2), (3, 2, 6, 2), (16, 1, 16, 1)]),
        make_level(
            "THE LAST TO WAKE", "THE FIRST BORROWERS MAY FINISH LAST.",
            [p(2, 6, 5), p(11, 7, NORTH), p(2, 7), p(13, 6), p(1, 2), b(16, 1)],
            [(5, 4), (13, 5), (6, 5), (13, 4), (1, 1)],
            [s(0), s(2), w(2), s(1), s(2), s(3), w(2), s(2), s(3), s(4),
             w(2), s(3), s(4), s(3), w(2), s(3), s(4), s(1),
             w(2), s(4), s(0), w(9), s(0), s(1), s(0),
             w(2), s(1), s(5), w(1), s(0)],
            "Pause both original travelers and circulate their fast horizontal and slow vertical loans through three later borrowers. Two fast boundary reversals set the handoff positions; glass then converts the long horizontal stride into a single step. Return that softened loan to the first pearl, whose mirror manufactures north again. The second original pearl has meanwhile returned through its own mirror. Exchange their axes one last time and finish the original pair after all three successors have settled.",
            rectangles=[(2, 6, 8, 6), (8, 4, 8, 6), (5, 4, 8, 4),
                        (11, 5, 11, 7), (11, 7, 16, 7), (13, 5, 13, 7),
                        (2, 7, 6, 7), (6, 5, 6, 7), (13, 6, 16, 6),
                        (16, 4, 16, 6), (13, 4, 16, 4), (1, 2, 4, 2),
                        (4, 1, 4, 2), (1, 1, 4, 1), (16, 1, 16, 1)],
            slash=[(8, 6)], backslash=[(11, 7)], glass=[(2, 1)]),
    ]


def _allocation_finales():
    levels = []

    # The fast loop can claim only one of its two nests. The corresponding
    # loan then participates in a live axis trade and a later reserved turn.
    s = Composition('THE ORDER OF BELONGING', 'AN ARRIVAL CAN OWE A FUTURE TURN.',
        [P(3,2,5), P(7,5,NORTH), P(16,1), P(10,1), P(16,4), B(16,7)],
        [[(2,2),(7,2),(7,6),(2,6),(2,2)],
         [(16,1),(16,7),(12,7),(12,3)],
         [(10,1),(10,7)], [(8,6),(10,6)],
         [(16,4),(14,4),(14,1)]],
        'Reserve the odd-parity loop nest for the fast pearl. Its fast vertical loan and the later horizontal arrival must turn two live travelers at plain corners. Their simultaneous deliveries then fund the last journey: keep its future vertical turn in the pocket during the horizontal approach, and use glass only after that turn.',
        slash=[(2,2),(7,6)], backslash=[(7,2),(2,6)], glass=[(14,2)])
    s.step(3).finish(0,7,4).exchange(2)
    s.step(3).finish(1,4,2).at(2,16,7,6).exchange(2).exchange(3)
    s.step(4).at(2,12,7,WEST).at(3,10,6,8)
    s.exchange(2).exchange(3).exchange(2)
    s.step(2).finish(3,8,6).exchange(4).finish(2,12,3)
    s.step(2).at(4,14,4,WEST).exchange(4).exchange(5)
    s.step(2).finish(4,14,1)
    levels.append(s.level())

    # The carrier's first glass crossing repairs a closed loop. It cannot
    # retire yet: two fast loans and a later horizontal turn are still owed.
    s = Composition('WHAT THE GLASS REMEMBERS', 'A USEFUL JOURNEY MAY NEED TO RETURN.',
        [P(3,2,5), P(12,1,6), P(8,1), P(10,7), P(16,3), B(1,7)],
        [[(2,2),(6,2),(6,6),(2,6),(2,2)], [(12,1),(12,3)],
         [(8,1),(8,4),(11,4)], [(10,1),(10,7)], [(10,5),(14,5)],
         [(16,1),(16,7)], [(13,4),(16,4)]],
        'Interrupt the glass carrier after its first crossing to soften the closed loop. Keep the displaced fast loan working through two plain-corner relays rather than parking it. The carrier later receives that fast loan back, rebounds through its glass again, and reaches its own corner exactly when the final horizontal delivery supplies its turn.',
        slash=[(2,2),(6,6)], backslash=[(6,2),(2,6)], glass=[(8,3)])
    s.step(1).finish(1,12,3).exchange(2)
    s.step(1).at(2,8,3,SOUTH).at(0,6,3,6)
    s.exchange(2).exchange(0).exchange(3)
    s.step(13).finish(0,4,2).at(3,10,5,6).exchange(3).exchange(4)
    s.step(4).finish(3,14,5).at(4,16,4,8).exchange(4).exchange(2)
    s.step(4).finish(4,13,4).at(2,8,4,SOUTH).exchange(2).exchange(5)
    s.step(4).finish(2,11,4)
    levels.append(s.level())

    return levels
