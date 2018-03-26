import unittest
from gym_watten.envs.watten_env cimport WattenEnv, Observation
from src.LookUp cimport LookUp, ModelOutput
from libcpp.vector cimport vector

class LookUpTest(unittest.TestCase):

    def test_memorize(self):
        """ Memorize """
        cdef WattenEnv env = WattenEnv()
        env.seed(1850)
        cdef Observation obs
        env.reset(&obs)
        cdef LookUp model = LookUp()
        cdef ModelOutput output

        for i in range(32):
            output.p[i] = 0
        output.p[4] = 1
        output.v = -1

        model.memorize(&obs, &output)

        cdef ModelOutput prediction
        model.predict_single(&obs, &prediction)
        self.assertEqual(prediction.p, output.p, "Wrong probability memorized")
        self.assertEqual(prediction.v, output.v, "Wrong value memorized")

    def test_memorize_multiple(self):
        cdef WattenEnv env = WattenEnv()
        env.seed(1850)
        cdef Observation obs
        env.reset(&obs)
        cdef LookUp model = LookUp()
        cdef ModelOutput output

        for i in range(32):
            output.p[i] = 0
        output.p[4] = 1
        output.v = -1
        model.memorize(&obs, &output)

        output.p[4] = 0
        output.p[12] = 1
        output.v = 0.5
        model.memorize(&obs, &output)

        output.p[4] = 0.5
        output.p[12] = 0.5
        output.v = -0.25
        cdef ModelOutput prediction
        model.predict_single(&obs, &prediction)
        self.assertEqual(prediction.p, output.p, "Wrong probability memorized")
        self.assertEqual(prediction.v, output.v, "Wrong value memorized")

    def test_predict_empty(self):
        cdef WattenEnv env = WattenEnv()
        env.seed(1850)
        cdef Observation obs
        env.reset(&obs)
        cdef LookUp model = LookUp()
        cdef ModelOutput output

        for i in range(32):
            output.p[i] = 1
        output.v = 0

        cdef ModelOutput prediction
        model.predict_single(&obs, &prediction)
        self.assertEqual(prediction.p, output.p, "Wrong probability memorized")
        self.assertEqual(prediction.v, output.v, "Wrong value memorized")

    def test_generate_key(self):
        cdef Observation obs
        for i in range(4):
            for j in range(8):
                for k in range(6):
                    obs.hand_cards[i][j][k] = 0
        for i in range(4):
            obs.tricks[i] = 0
        cdef LookUp model = LookUp()

        obs.hand_cards[0][1][0] = 1
        obs.hand_cards[2][5][0] = 1
        obs.hand_cards[1][4][0] = 1

        self.assertEqual(model.generate_key(&obs).decode("utf-8"), "1,12,21,------0-0", "Wrong key")

        obs.tricks[0] = 1
        obs.tricks[3] = 1
        self.assertEqual(model.generate_key(&obs).decode("utf-8"), "1,12,21,------1-2", "Wrong key")

        obs.hand_cards[1][4][0] = 0
        obs.hand_cards[1][4][1] = 1
        self.assertEqual(model.generate_key(&obs).decode("utf-8"), "1,21,-12-----1-2", "Wrong key")

        obs.hand_cards[0][2][2] = 1
        obs.hand_cards[0][3][4] = 1
        self.assertEqual(model.generate_key(&obs).decode("utf-8"), "1,21,-12-2--3--1-2", "Wrong key")

        obs.hand_cards[0][2][2] = 0
        obs.hand_cards[0][3][4] = 0
        obs.hand_cards[0][2][3] = 1
        obs.hand_cards[0][3][5] = 1
        self.assertEqual(model.generate_key(&obs).decode("utf-8"), "1,21,-12--2--3-1-2", "Wrong key")


    def test_argmax(self):
        cdef LookUp model = LookUp()
        cdef vector[float] values

        self.assertEqual(model.argmax(&values), -1, 'Wrong argmax (0)')

        values.push_back(1)
        self.assertEqual(model.argmax(&values), 0, 'Wrong argmax (1)')

        values.push_back(1)
        self.assertEqual(model.argmax(&values), 0, 'Wrong argmax (2)')

        values.push_back(5)
        self.assertEqual(model.argmax(&values), 2, 'Wrong argmax (3)')

        values.push_back(-2.63)
        self.assertEqual(model.argmax(&values), 2, 'Wrong argmax (4)')

    def test_valid_step(self):
        cdef LookUp model = LookUp()
        cdef WattenEnv env = WattenEnv()
        cdef float[32] values = [0, 0, 0, 4, -1, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        env.seed(42)
        env.reset()

        self.assertEqual(model.valid_step(values, &env.players[0].hand_cards), 7, 'Wrong valid step (0)')