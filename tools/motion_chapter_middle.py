"""Authored middle chapter for Borrowed Motion, rooms 11 through 37.

Every room has an explicit constructive solution. Helpers only express the
hand-authored passages and actions; they do not shuffle, reflect, or rename
existing rooms. Replay during construction checks that each proposed exchange
has a real effect and that the final placements satisfy the unchanged model.
"""
from dataclasses import replace

from generate_motion_levels import (
    Actor, Level, State, make_level, initial_state, swap, wind, replay, won,
    EAST, SOUTH, WEST, NORTH, FLOOR, WALL, SLASH, BACKSLASH, SLOWGLASS,
)

P = lambda x, y, motion=0: Actor(0, x, y, motion)
B = lambda x, y, motion=0: Actor(1, x, y, motion)


class Study:
    """A small authoring notation for exact exchanges and deliberate steps."""
    def __init__(self, name, hint, actors, paths, lesson, *, slash=(), backslash=(), glass=(), rooms=()):
        rectangles = list(rooms)
        for path in paths:
            for (x1, y1), (x2, y2) in zip(path, path[1:]):
                assert x1 == x2 or y1 == y2, (name, "Diagonal passage")
                rectangles.append((min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)))
        rectangles.extend((a.x, a.y, a.x, a.y) for a in actors)
        self.base = make_level(name, hint, actors, [], [], lesson, rectangles=rectangles,
                               slash=slash, backslash=backslash, glass=glass)
        self.state = initial_state(self.base)
        self.actions = []
        self.nests = []

    def exchange(self, actor):
        current = self.state.actors[actor]
        assert current.active and current.motion != self.state.pocket, (self.base.name, "No-op exchange", actor)
        self.state = swap(self.base, self.state, actor)
        self.actions.append(('swap', actor))
        return self

    def step(self, count):
        assert count > 0
        self.state = wind(self.base, self.state, count)
        self.actions.append(('wind', count))
        return self

    def arrive(self, actor, x, y, limit=128):
        # Authoring shorthand: follow an already chosen autonomous trajectory
        # to its first specified landing. This emits a concrete wind count.
        for count in range(1, limit+1):
            self.state = wind(self.base, self.state, 1)
            current = self.state.actors[actor]
            if (current.x, current.y) == (x, y):
                self.actions.append(('wind', count))
                return self
        raise AssertionError((self.base.name, "Chosen route misses landing", actor, x, y))

    def at(self, actor, x, y, motion=None):
        current = self.state.actors[actor]
        assert (current.x, current.y) == (x, y), (self.base.name, actor, current, (x, y))
        assert motion is None or current.motion == motion, (self.base.name, "Heading", current, motion)
        return self

    def finish(self, actor, x, y):
        self.at(actor, x, y)
        assert self.state.pocket == 0, (self.base.name, "Pocket must brake", self.state.pocket)
        assert (x, y) not in self.nests
        self.exchange(actor)
        actors = list(self.state.actors)
        actors[actor] = replace(actors[actor], active=False)
        self.state = replace(self.state, actors=tuple(actors))
        self.nests.append((x, y))
        return self

    def level(self):
        board = list(self.base.board)
        for x, y in self.nests:
            board[y*18+x] = 4
        level = replace(self.base, board=tuple(board), solution=tuple(self.actions))
        assert len(level.name) <= 24 and len(level.hint) <= 38
        assert len(self.nests) == sum(a.kind == 0 for a in level.actors)
        assert not any(a.kind == 0 and (a.x, a.y) in self.nests for a in level.actors)
        final, _ = replay(level)
        assert won(final), level.name
        assert final.actors == self.state.actors and final.pocket == self.state.pocket, level.name
        return level


def middle_levels():
    levels = []

    # 11. The only heading factory is a pearl that must remain unfinished.
    s = Study('THE UNFINISHED JOURNEY', 'SOME ARRIVALS MUST WAIT.',
        [P(3,4), P(9,6), P(14,2), B(1,7,EAST)],
        [[(1,4),(6,4),(6,1)], [(9,2),(9,6)], [(14,2),(14,6)]],
        'Keep the pearl with the only mirror unfinished while its vertical loan serves both shafts. A free wall rebound supplies the opposite sign without another factory visit; the factory must settle last.',
        slash=[(6,4)])
    s.exchange(3).exchange(0).step(3).at(0,6,4,NORTH).exchange(0)
    s.exchange(1).step(4).finish(1,9,2)
    s.exchange(2).step(5).finish(2,14,6)
    s.exchange(0).step(13).finish(0,1,4)
    levels.append(s.level())

    # 12. Horizontal preparation must precede the last horizontal-to-vertical loan.
    s = Study('PREPARED POSITIONS', 'MAKE ROOM FOR THE MOTION TO COME.',
        [P(2,2), P(9,2), P(2,6), B(16,7,EAST)],
        [[(2,2),(6,2),(6,6)], [(9,2),(12,2),(12,6)], [(2,6),(4,6),(4,7)]],
        'Prepare both unmarked corners before the third pearl turns the only eastward loan south. Completing that converter too early strands the unprepared pearls.',
        backslash=[(4,6)])
    s.exchange(3).exchange(0).step(4).at(0,6,2).exchange(0)
    s.exchange(1).step(3).at(1,12,2).exchange(1)
    s.exchange(2).step(3).finish(2,4,7)
    s.exchange(1).step(4).finish(1,12,6)
    s.exchange(0).step(4).finish(0,6,6)
    levels.append(s.level())

    # 13. Two different intermediate headings must be harvested from one route.
    s = Study('THE SECOND CORNER', 'A TURN CAN SERVE MORE THAN ITS ROAD.',
        [P(4,6), P(10,5), P(12,1), B(1,7,NORTH)],
        [[(4,6),(4,3),(7,3),(7,7)], [(10,5),(14,5)], [(12,1),(12,3),(15,3)]],
        'Prepare the small unmarked corner with the initial vertical loan before the factory converts it horizontally. Complete both horizontal branches before allowing the factory to make its final vertical descent.',
        slash=[(4,3)], backslash=[(7,3)])
    s.exchange(3).exchange(2).step(3).at(2,12,3,SOUTH).exchange(2)
    s.exchange(0).step(4).at(0,4,3,EAST).exchange(0)
    s.exchange(1).step(4).finish(1,14,5)
    s.exchange(2).step(3).finish(2,15,3)
    s.exchange(0).step(7).finish(0,7,7)
    levels.append(s.level())

    # 14. A four-pearl dependency tree, with a different loan at each corner.
    s = Study('THREE REQUESTS', 'LISTEN BEFORE CLOSING THE ARCHIVE.',
        [P(2,6), P(10,6), P(12,4), P(14,1), B(1,7,EAST)],
        [[(2,6),(7,6),(7,2),(3,2),(3,5)], [(10,2),(10,6)],
         [(12,4),(16,4),(16,1)], [(14,1),(14,2),(12,2)]],
        'Prepare the eastern corner horizontally, use the factory to lend a vertical heading to two branches, then harvest its second horizontal heading for the other unmarked corner. Axis changes, not opposite signs, determine the preparation order.',
        slash=[(7,6),(3,2)], backslash=[(7,2)])
    s.exchange(4).exchange(2).step(4).at(2,16,4).exchange(2)
    s.exchange(0).step(5).at(0,7,6,NORTH).exchange(0)
    s.exchange(2).step(3).finish(2,16,1)
    s.exchange(1).step(4).finish(1,10,2)
    s.exchange(3).step(2).at(3,14,2,SOUTH).exchange(3)
    s.exchange(0).step(5).at(0,7,2,WEST).exchange(0)
    s.exchange(3).step(2).finish(3,12,2)
    s.exchange(0).step(7).finish(0,3,5)
    levels.append(s.level())

    # 15. An arrival changes the axis of another live journey; its displaced
    # horizontal loan starts a third pearl rather than being parked wastefully.
    s = Study('CROSS PURPOSES', 'A FULL POCKET CAN START TWO PLANS.',
        [P(3,2,EAST), P(11,6,NORTH), P(3,6), B(16,7)],
        [[(3,2),(6,2),(6,1)], [(11,3),(11,6)], [(3,6),(8,6)]],
        'Let two moving pearls reach an arrival and a plain corner together. Braking the arrival turns the other pearl; its displaced horizontal loan starts the third. The one empty bell clears the pocket for the last delivery.')
    s.step(3).finish(1,11,3).exchange(0).exchange(2)
    s.step(1).finish(0,6,1).exchange(3).step(4).finish(2,8,6)
    levels.append(s.level())

    # 16. Three existing tokens and two storage bells. One live pearl needs a
    # second unmarked turn, so the two empty bells have distinct duties.
    s = Study('THE TWO EMPTY BELLS', 'STORAGE IS PART OF THE ROUTE.',
        [P(2,2,EAST), P(10,6,NORTH), P(14,1,SOUTH), B(1,7), B(16,7)],
        [[(2,2),(4,2),(4,4)], [(10,6),(10,4),(12,4),(12,6)],
         [(14,1),(14,3)]],
        'Three live motions form a displacement chain. The first bell accepts the unused vertical loan; the second accepts the horizontal loan displaced at a later corner. Freezing everything first exceeds the economical solution.')
    s.step(2).finish(2,14,3).exchange(0).exchange(1).exchange(3)
    s.step(2).finish(0,4,4).exchange(1).exchange(4)
    s.step(2).finish(1,12,6)
    levels.append(s.level())

    # 17. A near arrival supplies the fourth pearl while a longer mirrored
    # journey continues. Its later finish needs the one storage slot.
    s = Study('THE SHARED MINUTE', 'ONE ARRIVAL CAN FUND THE NEXT.',
        [P(2,2,EAST), P(10,6,NORTH), P(2,6), P(14,6), B(16,7)],
        [[(2,2),(6,2),(6,1)], [(10,2),(10,6)],
         [(2,6),(6,6),(6,4)], [(14,2),(14,6)]],
        'A first arrival turns one live pearl and launches another. The short turned journey then starts the fourth pearl while the mirror route continues, creating two staggered arrivals and one necessary storage exchange.',
        slash=[(6,6)])
    s.step(4).finish(1,10,2).exchange(0).exchange(2)
    s.step(1).finish(0,6,1).exchange(3)
    s.step(4).finish(3,14,2).exchange(4).step(1).finish(2,6,4)
    levels.append(s.level())

    # 18. Fast reversal deliberately changes the reachable stopping parity.
    s = Study('THE FAR SIDE OF FAST', 'A REBOUND CAN CHANGE YOUR LANDING.',
        [P(2,2,5), P(12,6,NORTH), P(4,6), B(16,7)],
        [[(2,2),(6,2)], [(12,6),(12,4),(8,4),(14,4)], [(4,3),(4,6)]],
        'Recover a fast horizontal loan from the first arrival and trade it for a slow vertical one. The fast carrier deliberately crosses its target line, then uses a wall rebound to reach the opposite parity while the slow carrier finishes.')
    s.step(2).finish(0,6,2).exchange(1).exchange(2)
    s.step(3).finish(2,4,3).exchange(3).step(2).finish(1,8,4)
    levels.append(s.level())

    # 19. Both unmarked corners must be changed as the useful axis becomes free.
    s = Study('BORROWED EXITS', 'TURN THE JOURNEY. PASS ON THE REST.',
        [P(2,2,EAST), P(11,6,NORTH), P(2,6), P(10,4), B(16,7)],
        [[(2,2),(5,2),(5,6)], [(11,3),(11,6)],
         [(2,6),(7,6),(7,2)], [(10,4),(15,4)]],
        'The first vertical arrival changes one live corner and starts a horizontal crossing. The second arrival supplies the missing vertical turn of the crossing; that displaced horizontal loan starts the last pearl. Both final arrivals require planned storage.')
    s.step(3).finish(1,11,3).exchange(0).exchange(2)
    s.step(5).finish(0,5,6).exchange(2).exchange(3)
    s.step(5).finish(3,15,4).exchange(4).finish(2,7,2)
    levels.append(s.level())

    # 20. A real closed mirror loop preserves fast stopping parity: no wall
    # exists on its trajectory to repair it. Another pearl must soften the loan.
    loop = [[(2,2),(6,2),(6,6),(2,6),(2,2)]]
    s = Study('THE MISSING LANDING', 'SOME CIRCLES NEED A GENTLER LOAN.',
        [P(3,2,5), P(10,2), P(10,6), B(16,7)],
        loop + [[(10,2),(15,2)], [(10,6),(15,6)]],
        'A closed fast loop permanently skips its nest. Borrow its motion for a glass-bound pearl, then share the slow horizontal loan with the remaining exhibit before returning it to the loop. A wall shortcut is absent from the loop itself.',
        slash=[(2,2),(6,6)], backslash=[(6,2),(2,6)], glass=[(12,2)])
    s.exchange(0).exchange(1).step(4).finish(1,15,2)
    s.exchange(2).step(5).finish(2,15,6)
    s.exchange(0).step(1).finish(0,4,2)
    levels.append(s.level())

    # 21. The fast loan displaced from a closed loop remains useful elsewhere.
    s = Study('THE OTHER HALF', 'TRADE SPEEDS WHILE BOTH ROADS LIVE.',
        [P(3,2,5), P(10,2,5), P(10,6), B(16,7)],
        loop + [[(10,2),(15,2)], [(10,6),(15,6)]],
        'A glass arrival supplies slow motion to the still-running closed loop. Its displaced fast loan serves a short lane where a wall rebound can reach the odd endpoint. Store that recovered loan so the slower loop can finish.',
        slash=[(2,2),(6,6)], backslash=[(6,2),(2,6)], glass=[(12,2)])
    s.step(4).finish(1,15,2).exchange(0).exchange(2)
    s.step(3).finish(2,15,6).exchange(3).step(4).finish(0,4,2)
    levels.append(s.level())

    # 22. A horizontal factory becomes vertical, then a loop recovers the axis
    # needed by the first exhibit. Neither loop can finish at its initial parity.
    s = Study('BETWEEN TWO CIRCLES', 'A SLOW LOAN STILL NEEDS ITS AXIS.',
        [P(3,2,5), P(14,3,6), P(7,2), B(16,7)],
        loop + [[(10,2),(14,2),(14,6),(10,6),(10,2)], [(7,2),(8,2),(8,6)]],
        'Send the first fast horizontal loan through a turning glass carrier. Exchange the resulting vertical motion into the other loop at a compatible edge, store its fast loan, then recover a horizontal finish for the first loop.',
        slash=[(2,2),(6,6),(10,2),(14,6)],
        backslash=[(6,2),(2,6),(14,2),(10,6),(8,2)], glass=[(8,4)])
    s.exchange(0).exchange(2).step(4).finish(2,8,6)
    s.exchange(1).exchange(3).step(11).finish(1,12,2)
    s.exchange(0).step(15).finish(0,4,2)
    levels.append(s.level())

    # 23. The glass carrier will return a different axis; prepare a plain corner
    # before sending away the horizontal loan, then obtain it again via a mirror.
    s = Study('BEFORE THE SOFTENING', 'PREPARE A PLACE FOR THE NEW LOAN.',
        [P(3,2,5), P(10,2), P(10,6), B(16,7)],
        loop + [[(10,2),(14,2),(14,6)], [(10,6),(12,6),(12,4),(13,4)]],
        'Stage a fast pearl at its unmarked corner before softening the only loan. The glass carrier returns vertical motion, which finishes the staged mirror route and recovers the horizontal motion needed by the closed loop.',
        slash=[(2,2),(6,6),(12,4)], backslash=[(6,2),(2,6),(14,2)], glass=[(12,2)])
    s.exchange(0).exchange(2).step(1).at(2,12,6).exchange(2)
    s.exchange(1).step(7).finish(1,14,6)
    s.exchange(2).step(4).finish(2,13,4)
    s.exchange(0).step(1).finish(0,4,2)
    levels.append(s.level())

    # 24. The concave loop has six corners, while the displaced fast vertical
    # loan must be slowed in a different exhibit before being handed on.
    s = Study('THE FOLDED ORBIT', 'FOLLOW THE LOAN THROUGH ITS CHANGES.',
        [P(3,2,5), P(12,6,NORTH), P(8,6), P(15,6), B(16,7)],
        [[(2,2),(7,2),(7,4),(5,4),(5,6),(2,6),(2,2)],
         [(12,3),(12,6)], [(8,4),(8,7)], [(15,2),(15,6)]],
        'Use an early vertical arrival to slow the concave orbit at a suitable corner. Its displaced fast vertical loan rebounds through glass, supplies another delivery, and leaves a stored motion while the orbit reaches its formerly skipped nest.',
        slash=[(2,2),(7,4),(5,4),(5,6)], backslash=[(7,2),(2,6)], glass=[(8,5)])
    s.step(3).finish(1,12,3).step(1).at(0,5,4,6).exchange(0).exchange(2)
    s.arrive(2,8,4).finish(2,8,4).exchange(3)
    s.arrive(3,15,2).finish(3,15,2).exchange(4)
    s.arrive(0,4,2).finish(0,4,2)
    levels.append(s.level())

    # 25. One gentle loan serves both loops; the spare fast token stays in a bell.
    s = Study('THE GLASS FERRY', 'ONE GENTLE LOAN CAN SERVE THEM ALL.',
        [P(2,1,5), P(11,1,5), P(9,6), B(16,7)],
        [[(1,1),(5,1),(5,4),(1,4),(1,1)],
         [(10,1),(14,1),(14,4),(10,4),(10,1)], [(8,6),(16,6)]],
        'Soften one circulating loan, use it to replace the other fast loop motion, and park that spare fast token in the bell. A single gentle loan can then serve both loops and the ferry; finishing the ferry before freeing that loan strands the circles.',
        slash=[(1,1),(5,4),(10,1),(14,4)],
        backslash=[(5,1),(1,4),(14,1),(10,4)], glass=[(12,6)])
    s.exchange(0).exchange(2).arrive(2,12,6).exchange(2)
    s.arrive(1,11,1).exchange(1).exchange(3)
    s.arrive(1,12,1).finish(1,12,1).exchange(0)
    s.arrive(0,3,1).finish(0,3,1).exchange(2)
    s.arrive(2,8,6).finish(2,8,6)
    levels.append(s.level())

    # 26. Three tokens fill the final two bells and pocket; every storage move
    # has a clear role, and three final arrivals can be resolved without a step.
    s = Study('THREE AT ONCE', 'LEAVE ROOM FOR EVERY ARRIVAL.',
        [P(2,2,EAST), P(8,6,NORTH), P(14,1,SOUTH), P(10,6), B(1,7), B(16,7)],
        [[(2,2),(4,2),(4,6)], [(8,6),(8,4),(12,4)],
         [(14,1),(14,3)], [(10,2),(10,6)]],
        'A first delivery rotates a chain of three live assignments. Their routes then finish together, with three different motions competing for an empty pocket and two bells. The full storage capacity is used deliberately.')
    s.step(2).finish(2,14,3).exchange(0).exchange(1).exchange(3)
    s.step(4).finish(0,4,6).exchange(4).finish(1,12,4).exchange(5).finish(3,10,2)
    levels.append(s.level())

    # 27. Slowing changes which event happens first, creating a new loan just
    # before a later crossing needs its missing perpendicular heading.
    s = Study('A LOAN BETWEEN ARRIVALS', 'LISTEN FOR THE NEXT USEFUL ENDING.',
        [P(2,2,5), P(12,6,NORTH), P(3,6), P(8,6), B(16,7)],
        [[(2,2),(6,2)], [(12,6),(12,4),(16,4)],
         [(3,2),(3,6)], [(8,6),(10,6),(10,2)]],
        'The fast first arrival turns one moving pearl and frees a vertical loan for another. Glass creates an earlier horizontal arrival, which prepares the fourth pearl exactly before the next vertical delivery supplies its turn.',
        glass=[(14,4)])
    s.step(2).finish(0,6,2).exchange(1).exchange(2)
    s.step(2).finish(1,15,4).exchange(3)
    s.step(2).finish(2,3,2).exchange(3).exchange(4)
    s.step(4).finish(3,10,2)
    levels.append(s.level())

    # 28. Five pearls form a three-stage live relay; no spare pearl needs to
    # be frozen merely to wait for its perpendicular heading.
    s = Study('THE FIVEFOLD PROMISE', 'EACH ENDING CHANGES THE NEXT ROAD.',
        [P(2,2,EAST), P(6,6,NORTH), P(9,6), P(10,2), P(6,1), B(16,7)],
        [[(2,2),(4,2),(4,6)], [(6,4),(6,6)], [(9,6),(12,6),(12,2)],
         [(10,2),(15,2),(15,5)], [(6,1),(10,1)]],
        'A sequence of three arrivals supplies perpendicular turns to other moving pearls. Each displaced horizontal loan launches the next waiting exhibit. The final short arrival must be stored while the last vertical traveler finishes.')
    s.step(2).finish(1,6,4).exchange(0).exchange(3)
    s.step(5).finish(0,4,6).exchange(3).exchange(2)
    s.step(3).finish(3,15,5).exchange(2).exchange(4)
    s.step(4).finish(4,10,1).exchange(5).step(1).finish(2,12,2)
    levels.append(s.level())

    # 29. Both delivery order and the unfinished central corner matter: the
    # sequence of useful axes is V, H, V, H rather than a single borrowed turn.
    s = Study('THE RELUCTANT MIRROR', 'THE USEFUL WAY CHANGES AS YOU GO.',
        [P(2,5), P(11,6,NORTH), P(2,2), P(14,6), B(16,7)],
        [[(2,5),(5,5),(5,2),(8,2)], [(11,6),(11,3),(15,3)],
         [(2,2),(3,2),(3,3)], [(14,4),(14,6)]],
        'The first delivery converts vertical motion into horizontal motion. Stage the central unmarked corner before the small mirrored delivery converts that loan back vertically; a final mirrored journey restores the horizontal axis.',
        slash=[(5,2),(11,3)], backslash=[(3,2)])
    s.step(7).finish(1,15,3).exchange(0).step(3).at(0,5,5).exchange(0)
    s.exchange(2).step(2).finish(2,3,3).exchange(3).step(3).finish(3,14,4)
    s.exchange(0).step(6).finish(0,8,2)
    levels.append(s.level())

    # 30. Nests are interchangeable, but their positions are not equally cheap
    # for every pearl. Preserve the crossroad pearl for the vertical nest.
    s = Study('THE RIGHTFUL NEST', 'A NEAR NEST MAY BELONG TO ANOTHER.',
        [P(4,4), P(1,4), P(9,6), P(14,2), B(16,7,EAST)],
        [[(1,4),(7,4)], [(4,1),(4,4)], [(9,6),(12,6),(12,2)], [(14,2),(16,2)]],
        'Reserve the crossroad pearl for the vertical nest. The outer horizontal pearl would need extra staging to claim it. Complete both horizontal-only exhibits before the converter changes the only loan vertically.',
        slash=[(12,6)])
    s.exchange(4).exchange(1).step(6).finish(1,7,4)
    s.exchange(3).step(2).finish(3,16,2)
    s.exchange(2).step(7).finish(2,12,2)
    s.exchange(0).step(3).finish(0,4,1)
    levels.append(s.level())

    # 31. Two moving pearls share a loop. The slow pearl could steal the fast
    # pearl's only reachable nest, but that leaves an expensive parity repair.
    shared_loop = [[(2,2),(7,2),(7,6),(2,6),(2,2)]]
    s = Study('WHICH PEARL BELONGS', 'THE FIRST ARRIVAL NEED NOT STAY.',
        [P(3,2,5), P(7,5,NORTH), P(10,2), P(14,6), B(16,7)],
        shared_loop + [[(10,2),(15,2)], [(14,4),(14,7)]],
        'Reserve the odd-parity loop nest for the fast pearl even though the slow pearl passes it first. The fast arrival launches a wall-assisted branch while the slower loop reaches the other nest; its recovered loan then completes the horizontal exhibit.',
        slash=[(2,2),(7,6)], backslash=[(7,2),(2,6)])
    s.step(3).finish(0,7,4).exchange(3)
    s.step(3).finish(3,14,4).exchange(4).finish(1,4,2)
    s.exchange(2).step(6).finish(2,15,2)
    levels.append(s.level())

    # 32. Three tokens, four pearls, two bells. Glass changes the order of
    # arrivals, so the player must leave storage free for the earlier finish.
    s = Study('THE WRONG SPEED', 'A NEW SPEED CHANGES WHO COMES FIRST.',
        [P(2,2,EAST), P(8,1,SOUTH), P(13,6,8), P(3,7), B(1,7), B(16,7)],
        [[(2,2),(4,2),(4,6)], [(8,1),(8,3)],
         [(13,6),(13,2),(15,2),(15,4)], [(3,1),(3,7)]],
        'An arrival trades three live assignments in sequence. The displaced fast vertical loan reaches glass and completes early, while two ordinary routes finish one step later. Both bells are needed to receive the recovered motions in that order.',
        backslash=[(15,2)], glass=[(3,4)])
    s.step(2).finish(1,8,3).exchange(0).exchange(2).exchange(3)
    s.step(3).finish(3,3,3).exchange(4)
    s.step(1).finish(0,4,6).exchange(5).finish(2,15,4)
    levels.append(s.level())

    # 33. A bounded vertical shuttle deliberately waits in motion. Freezing it
    # would consume two exchanges beyond this economical five-pearl relay.
    s = Study('THE WAITING KEY', 'YOU CAN WAIT WITHOUT STANDING STILL.',
        [P(2,2,EAST), P(6,6,NORTH), P(10,6), P(14,2), P(8,2), B(16,7)],
        [[(2,2),(4,2),(4,6)], [(6,4),(6,6)], [(10,3),(10,7)],
         [(10,3),(12,3)], [(10,2),(16,2),(16,5)], [(8,2),(8,4),(12,4)]],
        'Resolve two arrivals without stepping, then launch a mirrored converter and a vertical shuttle. The shuttle returns to its unmarked corner when the converter supplies horizontal motion; this moving wait avoids an otherwise unnecessary stop and restart.',
        slash=[(10,3)], backslash=[(16,2)])
    s.step(2).finish(1,6,4).exchange(0).exchange(3)
    s.step(5).finish(0,4,6).exchange(2).finish(3,16,5).exchange(4)
    s.step(8).finish(2,12,3).exchange(4).exchange(5)
    s.step(4).finish(4,12,4)
    levels.append(s.level())

    # 34. A single displaced loan passes through three changing exhibits while
    # the slow concave orbit remains live. The final storage decision frees it.
    s = Study('THE LONG CONVERSATION', 'PASS ON THE WAY, NOT JUST THE SPEED.',
        [P(3,2,5), P(12,6,NORTH), P(8,6), P(15,6), P(10,1), B(16,7)],
        [[(2,2),(7,2),(7,4),(5,4),(5,6),(2,6),(2,2)], [(12,3),(12,6)],
         [(8,4),(8,7)], [(15,6),(15,3),(16,3)], [(10,1),(14,1),(14,2)]],
        'A vertical arrival slows the concave orbit and displaces a fast loan. That loan passes through glass, a vertical-to-horizontal delivery, and a horizontal-to-vertical delivery before it can be stored to let the orbit rest.',
        slash=[(2,2),(7,4),(5,4),(5,6),(15,3)],
        backslash=[(7,2),(2,6),(14,1)], glass=[(8,5)])
    s.step(3).finish(1,12,3).step(1).exchange(0).exchange(2)
    s.arrive(2,8,4).finish(2,8,4).exchange(3)
    s.arrive(3,16,3).finish(3,16,3).exchange(4)
    s.arrive(4,14,2).finish(4,14,2).exchange(5)
    s.arrive(0,4,2).finish(0,4,2)
    levels.append(s.level())

    # 35. Five exhibits, one token, two different preparation waves. The large
    # converter may not finish until both waves have used its changing axis.
    s = Study('FOUR OPEN ACCOUNTS', 'PREPARE MORE THAN ONE TOMORROW.',
        [P(2,6), P(10,6), P(12,4), P(14,1), P(9,7), B(1,7,EAST)],
        [[(2,6),(7,6),(7,2),(3,2),(3,5)], [(10,2),(10,6)],
         [(12,4),(16,4),(16,1)], [(14,1),(14,2),(12,2)], [(9,7),(12,7),(12,5)]],
        'Prepare two distant horizontal corners before the factory makes its first vertical loan. After resolving those and the vertical shaft, prepare a different corner before the factory makes its next horizontal loan. The quota rewards grouping work by the axis currently available.',
        slash=[(7,6),(3,2)], backslash=[(7,2)])
    s.exchange(5).exchange(2).step(4).exchange(2)
    s.exchange(4).step(3).exchange(4)
    s.exchange(0).step(5).exchange(0)
    s.exchange(2).step(3).finish(2,16,1)
    s.exchange(4).step(2).finish(4,12,5)
    s.exchange(1).step(4).finish(1,10,2)
    s.exchange(3).step(2).exchange(3)
    s.exchange(0).step(5).exchange(0)
    s.exchange(3).step(2).finish(3,12,2)
    s.exchange(0).step(7).finish(0,3,5)
    levels.append(s.level())

    # 36. A fast perpendicular loan creates an early arrival; two later
    # arrivals can be resolved before moving, then the pocket holds a loan
    # while the last pearl travels into position for its unmarked turn.
    s = Study('AN APPOINTMENT IN GLASS', 'HOLD THE LOAN UNTIL ITS ROAD IS READY.',
        [P(2,2,EAST), P(6,7,8), P(10,6), P(13,2), P(8,2), B(16,7)],
        [[(2,2),(4,2),(4,6)], [(6,3),(6,7)], [(10,6),(10,2),(12,2)],
         [(13,2),(16,2),(16,5)], [(8,2),(8,4),(13,4)]],
        'The first fast arrival turns an ordinary journey into an early fast finish. Its loan then reaches a mirror at the same time as a separate slow delivery. Hold the recovered fast horizontal loan while the last pearl reaches its corner; exchange there and use glass for the final precise landing.',
        slash=[(10,2)], backslash=[(16,2)], glass=[(11,4)])
    s.step(2).finish(1,6,3).exchange(0).exchange(3)
    s.step(3).finish(0,4,6).exchange(2)
    s.step(3).finish(3,16,5).exchange(4).finish(2,12,2)
    s.step(2).exchange(4).exchange(5).step(4).finish(4,13,4)
    levels.append(s.level())

    # 37. Shared-loop nest assignment leads to a chain that changes axis after
    # the loop has already closed, with one fast token permanently parked.
    s = Study('THE LAST OPEN CIRCLE', 'CHOOSE WHO FINISHES, THEN WHAT LIVES.',
        [P(3,2,5), P(7,5,NORTH), P(10,2), P(14,6), P(10,6), B(16,7)],
        shared_loop + [[(10,2),(15,2),(15,5)], [(14,4),(14,7)], [(10,3),(10,6)]],
        'Assign the two loop nests by reachable parity and use the fast arrival for a short rebound. Park that fast token; the slow loop arrival must then finish a turning route to manufacture the vertical loan for the fifth pearl.',
        slash=[(2,2),(7,6)], backslash=[(7,2),(2,6),(15,2)])
    s.step(3).finish(0,7,4).exchange(3)
    s.step(3).finish(3,14,4).exchange(5).finish(1,4,2)
    s.exchange(2).step(9).finish(2,15,5)
    s.exchange(4).step(4).finish(4,10,3)
    levels.append(s.level())

    return levels
