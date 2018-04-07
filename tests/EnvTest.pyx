import unittest
from gym_watten.envs.watten_env cimport WattenEnv, Color, Value, Observation, Player, State

class EnvTest(unittest.TestCase):

    def test_init(self):
        cdef WattenEnv env = WattenEnv(True)
        self.assertEqual(env.players.size(), 2, "wrong number of players")
        self.assertEqual(env.cards.size(), 8, "wrong number of cards")

        for i in range(env.cards.size()):
            for j in range(i + 1, env.cards.size()):
                self.assertFalse(env.cards[i].color == env.cards[j].color and env.cards[i].value == env.cards[j].value, "duplicate cards")

            self.assertIn(env.cards[i].color, [Color.EICHEL, Color.GRUEN], "card with invalid color")
            self.assertIn(env.cards[i].value, [Value.SAU, Value.KOENIG, Value.OBER, Value.UNTER], "card with invalid value")

    def test_reset(self):
        cdef WattenEnv env = WattenEnv(True)
        cdef Observation obs
        env.reset()
        env.reset()
        env.reset()
        env.seed(42)
        env.reset(&obs)

        cdef Player* player
        for player in env.players:
            self.assertEqual(player.hand_cards.size(), 3, "wrong number of hand cards")
            self.assertEqual(player.tricks, 0, "tricks not reseted")

        hand_cards = [[[0 for i in range(6)] for i in range(8)] for i in range(4)]
        hand_cards[0][4][0] = 1
        hand_cards[1][4][0] = 1
        hand_cards[1][7][0] = 1

        self.assertEqual(obs.hand_cards, hand_cards, "wrong hand_cards obs")
        self.assertEqual(obs.tricks, [0, 0, 0, 0], "wrong tricks obs")

        self.assertTrue(env.table_card == NULL, "wrong table card")
        self.assertEqual(env.last_tricks.size(), 0, "last tricks not empty")
        self.assertEqual(env.current_player, 0, "wrong current player")
        self.assertFalse(env.is_done(), "game is not done")

    def test_step(self):
        cdef WattenEnv env = WattenEnv(True)
        cdef Observation obs
        env.seed(42)
        env.reset()
        env.step(3, &obs)

        hand_cards = [[[0 for i in range(6)] for i in range(8)] for i in range(4)]
        hand_cards[0][4][1] = 1
        hand_cards[0][6][0] = 1
        hand_cards[0][7][0] = 1
        hand_cards[1][6][0] = 1

        self.assertEqual(obs.hand_cards, hand_cards, "wrong hand_cards obs")
        self.assertEqual(obs.tricks, [0, 0, 0, 0], "wrong tricks obs")

        self.assertEqual(env.last_tricks.size(), 0, "last tricks not empty")
        self.assertTrue(env.table_card == env.cards[3], "wrong table card")
        self.assertEqual(env.current_player, 1, "wrong current player")
        self.assertFalse(env.is_done(), "game is not done")

    def test_step_trick(self):
        cdef WattenEnv env = WattenEnv(True)
        cdef Observation obs
        env.seed(42)
        env.reset()
        env.step(3)
        env.step(0, &obs)

        hand_cards = [[[0 for i in range(6)] for i in range(8)] for i in range(4)]
        hand_cards[0][4][3] = 1
        hand_cards[0][6][0] = 1
        hand_cards[0][7][2] = 1
        hand_cards[1][6][0] = 1

        self.assertEqual(obs.hand_cards, hand_cards, "wrong hand_cards obs")
        self.assertEqual(obs.tricks, [1, 0, 0, 0], "wrong tricks obs")

        self.assertEqual(env.last_tricks.size(), 2, "last tricks not empty")
        self.assertTrue(env.last_tricks[0] == env.cards[3], "wrong first card last tricks")
        self.assertTrue(env.last_tricks[1] == env.cards[0], "wrong second card last tricks")
        self.assertTrue(env.table_card == NULL, "wrong table card")
        self.assertEqual(env.current_player, 1, "wrong current player")
        self.assertFalse(env.is_done(), "game is not done")

    def test_step_win(self):
        cdef WattenEnv env = WattenEnv(True)
        cdef Observation obs
        env.last_winner = 1
        env.seed(42)
        env.reset()
        env.step(3)
        env.step(0)

        env.step(5)
        env.step(4)

        env.step(7)
        env.step(1, &obs)

        hand_cards = [[[0 for i in range(6)] for i in range(8)] for i in range(4)]
        hand_cards[1][7][4] = 1
        hand_cards[1][6][5] = 1

        hand_cards[1][4][2] = 1
        hand_cards[0][6][3] = 1

        self.assertEqual(obs.hand_cards, hand_cards, "wrong hand_cards obs")
        self.assertEqual(obs.tricks, [0, 1, 1, 0], "wrong tricks obs")

        self.assertTrue(env.table_card == NULL, "wrong table card")
        self.assertEqual(env.current_player, 0, "wrong current player")
        self.assertTrue(env.is_done(), "game is done")
        self.assertEqual(env.last_winner, 0, "incorrect winner")


    def test_step_invalid(self):
        cdef WattenEnv env = WattenEnv(True)
        env.seed(42)
        env.reset()
        env.step(0)

        self.assertTrue(env.is_done(), "game is done")
        self.assertTrue(env.invalid_move, "invalid move not set")
        self.assertEqual(env.last_winner, 1, "incorrect winner")

    def test_get_state(self):
        cdef WattenEnv env = WattenEnv(True)
        env.seed(42)
        env.reset()
        env.step(3)
        env.step(0)
        env.step(5)

        cdef State state = env.get_state()
        self.assertEqual(state.player0_hand_cards.size(), 2, "wrong number of hand cards (0)")
        self.assertEqual(state.player1_hand_cards.size(), 1, "wrong number of hand cards (1)")
        self.assertEqual(state.player0_tricks, 0, "wrong tricks (0)")
        self.assertEqual(state.player1_tricks, 1, "wrong tricks (1)")
        #self.assertEqual(state.lastTrick[0].id, 3, "wrong first card in last trick")
        #self.assertEqual(state.lastTrick[1].id, 0, "wrong second card in last trick")
        self.assertEqual(state.table_card.id, 5, "wrong table card")
        self.assertEqual(state.current_player, 0, "wrong current player")
        self.assertEqual(state.cards_left.size(), 2, "wrong number of cards left")

    def test_set_state(self):
        cdef WattenEnv env = WattenEnv(True)
        env.seed(1337)
        env.reset()

        cdef State state
        state.player0_hand_cards.push_back(env.cards[1])
        state.player1_hand_cards.push_back(env.cards[7])
        state.player1_hand_cards.push_back(env.cards[3])
        state.current_player = 1
        state.table_card = env.cards[4]
        state.last_tricks.push_back(env.cards[0])
        state.last_tricks.push_back(env.cards[2])
        state.player0_tricks = 1
        state.player1_tricks = 0
        env.set_state(&state)

        cdef Observation obs
        env.regenerate_obs(&obs)

        hand_cards = [[[0 for i in range(6)] for i in range(8)] for i in range(4)]
        hand_cards[0][7][3] = 1
        hand_cards[0][5][2] = 1
        hand_cards[1][7][1] = 1
        hand_cards[1][4][0] = 1
        hand_cards[0][4][0] = 1

        self.assertEqual(obs.hand_cards, hand_cards, "wrong hand_cards obs")
        self.assertEqual(obs.tricks, [0, 0, 1, 0], "wrong tricks obs")

        self.assertEqual(env.current_player, 1, "wrong current player")
        for i in range(state.last_tricks.size()):
            self.assertTrue(env.last_tricks[i] == state.last_tricks[i], "wrong last trick, " + str(i))
        self.assertEqual(env.players[0].hand_cards.size(), 1, "wrong hand cards size")
        self.assertEqual(env.players[0].hand_cards[0].id, 1, "wrong hand card")
        self.assertEqual(env.table_card.id, 4, "wrong hand card")