"""Eighteen authored expert rooms (38–55) of Borrowed Motion.

These are exchange-budget puzzles.  Their witnesses deliberately use arrivals
as direction donors, and use full pockets to turn journeys already in flight.
Waiting is free: route length alone is never the intended difficulty.  The
lesson on every room records the decision the particular arrangement explores.
Witnesses are economical authored routes, not claims of mathematical optima.
"""
from generate_motion_levels import Actor, EAST, SOUTH, WEST, NORTH, make_level


def expert_levels():
    p = lambda x, y, motion=0: Actor(0, x, y, motion)
    b = lambda x, y, motion=0: Actor(1, x, y, motion)
    s = lambda actor: ('swap', actor)
    w = lambda beats: ('wind', beats)
    return [
        # 38. A first three-way relay: north is reused at two bare junctions.
        make_level(
            "DOUBLE ENTRY", "AN ARRIVAL CAN PAY FOR A TURN.",
            [p(12, 7, NORTH), p(2, 6, EAST), p(3, 2), b(1, 7)],
            [(12, 4), (5, 3), (6, 1)],
            [w(3), s(0), s(1), s(2), w(3), s(1), s(2), s(3), w(1), s(2)],
            "The first northward arrival turns the eastbound pearl; its displaced eastward motion launches the third. Capture the second arrival to turn the third at its unmirrored junction. Freezing both travelers first spends the exchange allowance on storage instead of these turns.",
            rectangles=[(12, 4, 12, 7), (2, 6, 8, 6), (5, 3, 5, 6),
                        (3, 2, 6, 2), (6, 1, 6, 3), (1, 7, 2, 7)]),
        # 39. A wall changes the unused return loan while a U-turn is in flight.
        make_level(
            "THE RETURN ADDRESS", "A BOUNCE CHANGES WHAT YOU OWE.",
            [p(2, 2, EAST), p(12, 7, NORTH), p(4, 7), b(1, 7)],
            [(6, 2), (13, 1), (1, 1)],
            [w(4), s(0), s(1), s(2), w(7), s(1), s(2), s(3), w(3), s(2)],
            "Export east from the first arrival, then export west after the long two-mirror route. The third pearl has used the intervening seven steps to reach the top wall and reverse; the captured westward loan takes it directly toward the final nest, while the bell receives the resulting southward debt.",
            rectangles=[(2, 2, 6, 2), (12, 3, 15, 3), (12, 3, 12, 7),
                        (15, 1, 15, 3), (1, 1, 15, 1), (4, 1, 4, 7), (1, 7, 2, 7)],
            slash=[(15, 3)], backslash=[(15, 1)]),
        # 40. Fast motion changes heading twice before each subsequent handoff.
        make_level(
            "THREE SIGNATURES", "A LONG STRIDE CAN SIGN THREE LOANS.",
            [p(1, 1, 5), p(3, 7, NORTH), p(13, 7), p(16, 7), b(1, 7)],
            [(7, 1), (7, 2), (14, 1), (13, 3)],
            [w(3), s(0), s(1), s(2), w(5), s(1), s(2), s(3),
             w(4), s(2), s(3), s(4), w(2), s(3)],
            "Relay a fast eastward loan through a north-then-west hook and a north-then-east hook. Each capture turns the next slow traveler at a bare junction. The last eastward loan must bounce immediately: its failed first microstep consumes half the step and repairs the landing parity.",
            rectangles=[(1, 1, 14, 1), (5, 2, 13, 2), (3, 4, 3, 7),
                        (3, 4, 16, 4), (9, 2, 9, 4), (10, 1, 10, 2),
                        (13, 2, 13, 7), (16, 3, 16, 7), (13, 3, 16, 3), (1, 7, 1, 7)],
            slash=[(9, 4), (10, 1)], backslash=[(9, 2), (10, 2)]),
        # 41. All three tokens start on pearls, not safely in bells.
        make_level(
            "THREE OPEN ACCOUNTS", "ONE ARRIVAL TURNS TWO JOURNEYS.",
            [p(2, 2, EAST), p(7, 7, NORTH), p(16, 6, 7), b(1, 7), b(15, 1)],
            [(5, 2), (11, 4), (10, 2)],
            [w(3), s(0), s(1), s(2), s(3), w(4), s(1), s(4), s(2)],
            "At the same instant an eastbound pearl arrives, a northbound pearl reaches its eastward branch and a fast westbound pearl reaches its northward branch. Chain the full-pocket trades before advancing. Both bells are needed to absorb the three surviving motion tokens by the final capture.",
            rectangles=[(2, 2, 5, 2), (7, 4, 7, 7), (7, 4, 11, 4),
                        (10, 6, 16, 6), (10, 2, 10, 6), (1, 7, 1, 7), (15, 1, 15, 1)]),
        # 42. Delay irreversible slowing until the fast loan has served its hook.
        make_level(
            "THE GLASS RESERVE", "SAVE THE GLASS FOR THE LAST LEG.",
            [p(1, 1, 5), p(2, 7, NORTH), p(14, 6, WEST), p(16, 3), b(1, 7), b(16, 1)],
            [(5, 1), (6, 7), (12, 3), (13, 7)],
            [w(2), s(0), s(1), s(2), s(3), w(3), s(1), s(3), s(4),
             s(2), s(5), w(3), s(3)],
            "The first capture launches a chain of three different headings. A fast hooked route and a slow northward route finish together while the fourth pearl reaches its turning point. Use the fast southward arrival there, surrender the spare motions to the bells, and let glass shorten only the final stride.",
            rectangles=[(1, 1, 5, 1), (2, 5, 2, 7), (2, 5, 6, 5),
                        (6, 5, 6, 7), (12, 6, 14, 6), (12, 3, 12, 6),
                        (12, 3, 16, 3), (13, 3, 13, 7), (1, 7, 1, 7), (16, 1, 16, 1)],
            backslash=[(6, 5)], glass=[(13, 5)]),
        # 43. No opening arrival: both moving pearls need each other's heading.
        make_level(
            "BEFORE THE FIRST REST", "TRADE BEFORE CLAIMING AN ARRIVAL.",
            [p(2, 6, EAST), p(9, 7, NORTH), p(6, 2), b(1, 7)],
            [(4, 3), (12, 2), (9, 1)],
            [w(2), s(0), s(1), s(0), w(3), s(0), s(1), s(2),
             w(3), s(1), s(2), s(3), w(1), s(2)],
            "Before any pearl can settle, exchange the headings of the two travelers using the pocket as a temporary buffer. Their new routes create the later arrival-to-junction relay. Taking the first loan is a temporary stop, not a delivery; deciding when to return it is the opening problem.",
            rectangles=[(2, 6, 4, 6), (4, 3, 4, 6), (9, 5, 9, 7),
                        (9, 5, 12, 5), (12, 2, 12, 5), (6, 2, 12, 2),
                        (9, 1, 9, 2), (1, 7, 1, 7)]),
        # 44. A full pocket stores a future turn throughout a vertical journey.
        make_level(
            "THE FORWARD POCKET", "KEEP THE NEXT TURN IN YOUR POCKET.",
            [p(2, 6, EAST), p(2, 7, EAST), p(5, 7), b(1, 1)],
            [(8, 4), (12, 3), (11, 3)],
            [w(8), s(0), w(1), s(1), s(2), w(4), s(1), w(2),
             s(2), w(4), s(2), s(3), w(1), s(2)],
            "The first pearl's mirror route manufactures north from a horizontal token. Its arrival turns the second traveler and releases east for the third. Capture the next northward arrival, then hold the displaced eastward loan throughout the last pearl's climb. An occupied nest becomes its turning point: spend the saved eastward loan there rather than parking and fetching it again.",
            rectangles=[(2, 6, 8, 6), (8, 3, 8, 6), (8, 3, 12, 3),
                        (2, 7, 11, 7), (11, 3, 11, 7), (5, 4, 5, 7),
                        (5, 4, 8, 4), (1, 1, 1, 1)], slash=[(8, 6)]),
        # 45. Two independent pairs need axis exchanges, separated by deliveries.
        make_level(
            "DOUBLE COUNTERPOINT", "THE SECOND PAIR MUST TRADE TOO.",
            [p(2, 6, EAST), p(8, 7, NORTH), p(12, 7), p(2, 2), b(1, 7)],
            [(4, 3), (11, 5), (15, 4), (7, 1)],
            [w(2), s(0), s(1), s(0), w(3), s(0), s(2), s(1), s(3),
             w(3), s(2), s(3), s(2), w(3), s(2), s(4), s(3)],
            "Exchange the first pair's axes at their plain elbows. Their arrivals launch the second pair, which also needs an axis exchange rather than two isolated loans. Only after both pairs have been routed does the bell absorb the spare token. The small final mirror changes the landing row without another exchange.",
            rectangles=[(2, 6, 4, 6), (4, 3, 4, 6), (8, 5, 8, 7),
                        (8, 5, 11, 5), (12, 4, 12, 7), (12, 4, 15, 4),
                        (2, 2, 5, 2), (5, 1, 5, 2), (5, 1, 7, 1), (1, 7, 1, 7)],
            slash=[(5, 1)]),
        # 46. A third initially moving token keeps time during the first trade.
        make_level(
            "THE THIRD VOICE", "THE THIRD JOURNEY HAS ALREADY BEGUN.",
            [p(2, 6, EAST), p(8, 7, NORTH), p(16, 2, 7), b(1, 7), b(15, 7)],
            [(4, 3), (11, 7), (6, 1)],
            [w(2), s(0), s(1), s(0), w(3), s(0), s(2), s(3),
             w(2), s(1), s(4), s(2)],
            "An initial three-exchange axis trade routes the first two pearls while the fast third pearl keeps moving. The first delivery coincides with its bare northward junction. Route it using the arriving northward token, then use both bells to retain all three tokens as the remaining pearls settle.",
            rectangles=[(2, 6, 4, 6), (4, 3, 4, 6), (8, 5, 8, 7),
                        (8, 5, 11, 5), (11, 5, 11, 7), (6, 2, 16, 2),
                        (6, 1, 6, 2), (1, 7, 1, 7), (15, 7, 15, 7)],
            backslash=[(11, 5)]),
        # 47. Three concurrent tokens, a fast reversal, and a fourth borrower.
        make_level(
            "THE FOURTH HAND", "THE LAST BORROWER NEEDS TWO AXES.",
            [p(3, 1, 6), p(15, 3, WEST), p(2, 7, EAST), p(10, 2), b(15, 7), b(2, 1)],
            [(1, 4), (13, 6), (7, 5), (12, 1)],
            [w(2), s(0), s(1), s(0), w(3), s(0), s(2), s(3), s(1), s(4),
             w(2), s(2), s(3), s(5), w(1), s(3)],
            "The opening pair exchanges a fast vertical token and a slow horizontal token. A mirror makes the first arrival a northward donor; a fast wall reversal puts the second pearl on its otherwise skipped row. Meanwhile the third arrival must turn the fourth borrower, so neither spare token can be parked indiscriminately.",
            rectangles=[(3, 1, 3, 5), (1, 5, 3, 5), (1, 4, 1, 5),
                        (13, 3, 15, 3), (13, 3, 13, 7), (2, 7, 7, 7),
                        (7, 5, 7, 7), (10, 2, 12, 2), (12, 1, 12, 2),
                        (15, 7, 15, 7), (2, 1, 2, 1)], backslash=[(1, 5)]),
        # 48. Two fast loans return as slow loans on different axes.
        make_level(
            "THE SECOND TEMPO", "GLASS CHANGES WHEN THE LOAN RETURNS.",
            [p(1, 6, 5), p(10, 7, 8), p(7, 7), p(11, 1), b(1, 1)],
            [(5, 2), (14, 5), (8, 7), (13, 4)],
            [w(2), s(0), s(1), s(0), w(4), s(0), s(2), s(1), s(3),
             w(3), s(2), s(3), s(2), w(2), s(2), s(4), s(3)],
            "Exchange two fast axes before either route enters glass. One window cancels a first microstep, the other follows a mirror after a full fast step; count their now-slow arrivals together. Those two loans start a second pair whose routes manufacture a horizontal/vertical exchange at different junctions.",
            rectangles=[(1, 6, 5, 6), (5, 2, 5, 6), (10, 3, 10, 7),
                        (10, 3, 14, 3), (14, 3, 14, 5), (7, 5, 7, 7),
                        (7, 5, 9, 5), (8, 5, 8, 7), (11, 1, 11, 4),
                        (11, 4, 13, 4), (1, 1, 1, 1)],
            backslash=[(14, 3)], slash=[(7, 5)], glass=[(5, 5), (14, 4)]),
        # 49. The launching bell must return as storage for a different token.
        make_level(
            "THE EMPTY CHAIR", "RETURN A DIFFERENT LOAN TO THE BELL.",
            [p(2, 2, NORTH), p(10, 1, SOUTH), p(6, 7), p(13, 1), b(2, 7, EAST), b(16, 1)],
            [(5, 2), (15, 4), (6, 4), (16, 6)],
            [s(4), s(0), s(2), w(3), s(0), s(1), s(3), s(2), s(4),
             w(5), s(1), s(3), s(5), w(3), s(3)],
            "Borrow the bell's horizontal movement to turn an already moving pearl; pass its old vertical movement to the third pearl. The first arrival turns the second and launches the fourth. Return the third pearl's northward token to the original bell, preserving a different free slot for the later southward debt.",
            rectangles=[(2, 2, 5, 2), (10, 1, 10, 4), (10, 4, 15, 4),
                        (6, 4, 6, 7), (13, 1, 13, 6), (13, 6, 16, 6),
                        (2, 7, 2, 7), (16, 1, 16, 1)]),
        # 50. Two heading permutations occur before the first settlement.
        make_level(
            "THE CROSS INDEX", "THE SAME PAIR MUST TRADE AGAIN.",
            [p(1, 6, EAST), p(8, 7, NORTH), p(16, 2, WEST), b(1, 1), b(16, 7)],
            [(6, 4), (10, 2), (9, 1)],
            [w(2), s(0), s(1), s(0), w(2), s(0), s(1), s(0),
             w(3), s(1), s(2), s(3), s(0), s(4), w(1), s(2)],
            "The first two pearls each need a staircase, requiring an axis trade and then a second trade at a different pair of elbows. The third traveler continues throughout. Of the two simultaneous arrivals, only the vertical one can turn it into its final branch without a further conversion trip.",
            rectangles=[(1, 6, 3, 6), (3, 4, 3, 6), (3, 4, 6, 4),
                        (8, 5, 8, 7), (8, 5, 10, 5), (10, 2, 10, 5),
                        (9, 2, 16, 2), (9, 1, 9, 2), (1, 1, 1, 1), (16, 7, 16, 7)]),
        # 51. Three coordinated plain turns precede a second generation of loans.
        make_level(
            "COMPOUND INTEREST", "BORROW THE SAME AXES MORE THAN ONCE.",
            [p(2, 6, EAST), p(10, 7, NORTH), p(8, 7), p(2, 1), b(16, 7)],
            [(6, 2), (14, 3), (11, 4), (5, 3)],
            [w(2), s(0), s(1), s(0), w(2), s(0), s(1), s(0),
             w(2), s(0), s(1), s(0), w(2), s(0), s(2), s(1), s(3),
             w(3), s(2), s(3), s(2), w(3), s(2), s(4), s(3)],
            "Route the opening pair through three successive unmirrored elbows by reusing both tokens rather than storing and fetching them for each pearl separately. Their arrivals seed a fresh pair that also needs an axis trade. The upper borrower then uses a wall reversal to turn the captured northward loan into its required southward leg.",
            rectangles=[(2, 6, 4, 6), (4, 4, 4, 6), (4, 4, 6, 4),
                        (6, 2, 6, 4), (10, 5, 10, 7), (10, 5, 12, 5),
                        (12, 3, 12, 5), (12, 3, 14, 3), (8, 4, 8, 7),
                        (8, 4, 11, 4), (2, 1, 5, 1), (5, 1, 5, 3), (16, 7, 16, 7)]),
        # 52. Mixed speed changes the location of one coordinated elbow.
        make_level(
            "DUPLEX GLASS", "ONE SHORT STRIDE MOVES THE TURN.",
            [p(1, 6, 5), p(11, 7, NORTH), p(3, 7), p(16, 1), b(1, 1)],
            [(8, 2), (16, 3), (1, 5), (14, 2)],
            [w(2), s(0), s(1), s(0), w(2), s(0), s(1), s(0),
             w(2), s(0), s(1), s(0), w(2), s(0), s(2), s(1), s(3),
             w(2), s(2), s(3), s(2), w(2), s(2), s(4), s(3)],
            "A fast horizontal token and a slow vertical token repeatedly exchange owners. Glass interrupts the fast token on the first microstep of a step, moving the next elbow one tile short of the naive two-tile landing. After the first pair settles, a second axis trade and two boundary reversals finish the remaining borrowers without fetching stored motions.",
            rectangles=[(1, 6, 5, 6), (5, 4, 5, 6), (5, 4, 8, 4),
                        (8, 2, 8, 4), (11, 5, 11, 7), (11, 5, 15, 5),
                        (15, 3, 15, 5), (15, 3, 16, 3), (3, 5, 3, 7),
                        (1, 5, 3, 5), (14, 1, 16, 1), (14, 1, 14, 2), (1, 1, 1, 1)],
            glass=[(8, 4)]),
        # 53. Holding a loan makes consecutive turns cheaper than bell retrieval.
        make_level(
            "THE POCKET PILGRIM", "YOUR POCKET CAN TRAVEL WITH A TURN.",
            [p(2, 6, EAST), p(8, 7, NORTH), p(2, 2), b(16, 7)],
            [(4, 4), (12, 1), (7, 1)],
            [w(2), s(0), s(1), s(0), w(2), s(0), s(1), w(2), s(1),
             w(2), s(1), w(2), s(2), s(1), w(3), s(2), w(1), s(2),
             w(2), s(3), s(2)],
            "After the opening pair trades axes, one settles and its loan stays in the pocket through the other's entire staircase. Each full-pocket exchange both turns the pearl and saves its previous heading for the next elbow. The last borrower clears the pocket just in time for a brake, then performs its own two turns with the same pair of retained directions.",
            rectangles=[(2, 6, 4, 6), (4, 4, 4, 6), (8, 5, 8, 7),
                        (8, 5, 10, 5), (10, 3, 10, 5), (10, 3, 12, 3),
                        (12, 1, 12, 3), (2, 2, 5, 2), (5, 1, 5, 2),
                        (5, 1, 7, 1), (16, 7, 16, 7)]),
        # 54. Three loans rotate before a two-loan ending can be established.
        make_level(
            "THE THREE KEYS", "CHOOSE WHICH LOAN TO LEAVE UNUSED.",
            [p(2, 6, EAST), p(8, 7, NORTH), p(14, 1, 6), p(2, 7), b(1, 1), b(16, 1)],
            [(4, 4), (10, 4), (16, 5), (4, 5)],
            [w(2), s(0), s(2), s(1), s(0), w(2), s(0), s(3), s(2), s(1), s(4),
             w(2), s(1), s(3), s(1), w(2), s(1), s(5), s(3)],
            "Rotate three loans through the pocket at the first set of junctions. The fast vertical token must rebound onto a different row before the horizontal arrival replaces it. Start the fourth pearl with the first northward arrival, retire the now-unneeded fast loan, and trade the two surviving journey axes once more before the final brakes.",
            rectangles=[(2, 6, 4, 6), (4, 4, 4, 6), (8, 5, 8, 7),
                        (8, 6, 10, 6), (10, 4, 10, 6), (14, 1, 14, 5),
                        (14, 5, 16, 5), (2, 5, 2, 7), (2, 5, 4, 5),
                        (1, 1, 1, 1), (16, 1, 16, 1)]),
        # 55. Five destinations; the same two loans outlive four generations.
        make_level(
            "FIVE POINT PROOF", "TWO LOANS CAN DRAW A CONSTELLATION.",
            [p(1, 6, EAST), p(8, 7, NORTH), p(13, 7), p(6, 7), p(2, 2), b(16, 1)],
            [(5, 4), (10, 3), (15, 5), (12, 3), (7, 3)],
            [w(2), s(0), s(1), s(0), w(2), s(0), s(1), s(0),
             w(2), s(0), s(2), s(1), s(3), w(2), s(2), s(3), s(2),
             w(2), s(2), s(3), s(4), w(2), s(3), s(4), s(3),
             w(4), s(3), s(4), s(5), w(3), s(4)],
            "Two exchanges of axes route the opening pair and create loans for two successors. Those successors trade axes; the next arrival both turns its partner and starts the fifth pearl. A further heading exchange sends one pearl through an already occupied nest while the other reverses at the top boundary. The last arrival supplies the final eastward turn. Every new borrower inherits work already done by an earlier one.",
            rectangles=[(1, 6, 3, 6), (3, 4, 3, 6), (3, 4, 5, 4),
                        (8, 5, 8, 7), (8, 5, 10, 5), (10, 3, 10, 5),
                        (13, 7, 15, 7), (15, 5, 15, 7), (6, 5, 6, 7),
                        (6, 5, 8, 5), (8, 3, 8, 5), (8, 3, 12, 3),
                        (2, 2, 4, 2), (4, 1, 4, 3), (4, 3, 7, 3), (16, 1, 16, 1)]),
    ]
