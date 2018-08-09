from gym_watten.envs.watten_env cimport WattenEnv, Observation, ActionType, State, Card
from src.Model cimport Model, ModelOutput
from src.ModelRating cimport ModelRating
from libcpp.vector cimport vector
from libcpp cimport bool
from time import sleep
from libc.stdlib cimport rand
import matplotlib.pyplot as plt
import pydot_ng as pydot
from io import BytesIO
import itertools
from math import exp
import pickle

ctypedef vector[Card*] HandCards

cdef class Game:

    def __cinit__(self, WattenEnv env):
        self.env = env
        self.mean_game_length = 0
        self.mean_v_p1 = 0
        self.mean_v_p2 = 0

    cpdef int match(self, Model agent1, Model agent2, bool render=False, bool reset=True):
        cdef Observation obs
        cdef ModelOutput output
        cdef int a, game_length = 0
        cdef float v_p1 = 0, v_p2 = 0
        if reset:
            self.env.reset(&obs)
        else:
            self.env.regenerate_obs(&obs)

        while not self.env.is_done():
            if self.env.next_action_type == ActionType.DRAW_CARD:
                game_length += 1

            if self.env.current_player == 0:
                agent1.predict_single(&obs, &output)
                if self.env.next_action_type == ActionType.DRAW_CARD:
                    v_p1 += output.v
                a = agent1.valid_step(output.p, &self.env.players[self.env.current_player].hand_cards)
            else:
                agent2.predict_single(&obs, &output)
                if self.env.next_action_type == ActionType.DRAW_CARD:
                    v_p2 += output.v
                a = agent2.valid_step(output.p, &self.env.players[self.env.current_player].hand_cards)

            self.env.step(a, &obs)

            if render:
                self.env.render('human')
                sleep(2)
           # if env.lastTrick  is not None:
            #    break

        self.mean_v_p1 += v_p1 / (game_length / 2)
        self.mean_v_p2 += v_p2 / (game_length / 2)
        self.mean_game_length += game_length

        return self.env.last_winner

    """cdef float compare(self, LookUp agent1, LookUp agent2):
        cdef vector[LookUp] agents
        agents.push_back(agent1)
        agents.push_back(agent2)
        first_player_wins = 0

        for i in range(10000):
            start_player = rand() % 2
            winner = self.match([agents[start_player], agents[1 - start_player]])
            first_player_wins += ((winner == 0) == (start_player == 0))
            #print(start_player, winner)

        return first_player_wins / 10000"""

    cpdef float compare_given_games(self, Model agent1, Model agent2, ModelRating rating):
        cdef int i, first_player_wins, winner, start_player
        first_player_wins = 0

        for i in range(rating.eval_games.size()):
            for start_player in range(2):
                self.env.set_state(&rating.eval_games[i])
                self.env.current_player = start_player
                winner = self.match(agent1, agent2, render=False, reset=False)
                first_player_wins += (winner == 0)

        return <float>first_player_wins / (rating.eval_games.size() * 2)

    cpdef float compare_rand_games(self, Model agent1, Model agent2, int number_of_games):
        cdef int i, first_player_wins, winner
        first_player_wins = 0

        self.mean_game_length = 0
        self.mean_v_p1 = 0
        self.mean_v_p2 = 0

        for i in range(number_of_games):
            self.env.reset()
            self.env.current_player = rand() % 2
            winner = self.match(agent1, agent2, render=False, reset=False)
            first_player_wins += (winner == 0)

        self.mean_game_length /= number_of_games
        self.mean_v_p1 /= number_of_games
        self.mean_v_p2 /= number_of_games

        return <float>first_player_wins / number_of_games

    cdef game_tree_step(self, Model model, Observation obs, dot, parent_node, prob, joint_prob, next_id, key, table, tree_only, true_edge_prob):
        cdef ModelOutput output
        cdef State game_state
        cdef vector[Card*] hand_cards = self.env.players[self.env.current_player].hand_cards

        node_key = key + "-"
        for card in hand_cards:
            node_key += str(card.id) + ","

        if tree_only:
            text = "P0: " + str([self.env.filename_from_card(card).decode("utf-8")  for card in self.env.players[0].hand_cards]) + " (" + str(self.env.players[0].tricks) + ")" + (" -" if self.env.current_player is 0 else "") + '\n'
            text += "P1: " + str([self.env.filename_from_card(card).decode("utf-8")  for card in self.env.players[1].hand_cards]) + " (" + str(self.env.players[1].tricks) + ")" + (" -" if self.env.current_player is 1 else "") + '\n'
            text += "T: " + (self.env.filename_from_card(self.env.table_card).decode("utf-8")  if self.env.table_card is not NULL else "-") + '\n'
            text += '%.4f' % joint_prob + "," + node_key
            node = pydot.Node(str(next_id), label=text)
            dot.add_node(node)
            if parent_node is not None:
                dot.add_edge(pydot.Edge(parent_node.get_name(), node.get_name(), label='%.2f' % true_edge_prob + " , " + '%.2f' % prob))
            next_id += 1
        else:
            node = None

        win_prob_per_action = []
        if self.env.is_done():
            total_win_prob = 1 if self.env.last_winner is 0 else 0
        else:
            model.predict_single(&obs, &output)
            game_state = self.env.get_state()

            sum = 0
            for card in hand_cards:
                sum += output.p[card.id]
            total_win_prob = 0
            current_player = self.env.current_player
            index = 0
            for card in hand_cards:
                self.env.set_state(&game_state)
                self.env.step(card.id, &obs)
                next_id, win_prob = self.game_tree_step(model, obs, dot, node, output.p[card.id] / sum, joint_prob * output.p[card.id] / sum, next_id, key + "," + str(card.id), table, tree_only, table[node_key][index] if tree_only else 0)
                win_prob_per_action.append(win_prob if current_player is 0 else (1 - win_prob))
                total_win_prob += win_prob * output.p[card.id] / sum
                index += 1

        if not tree_only:
            if node_key not in table:
                table[node_key] = []
            table[node_key].append([joint_prob, win_prob_per_action])

        return next_id, total_win_prob

    cpdef draw_game_tree(self, Model model, ModelRating modelRating, use_cache, tree_ind):

        dot = pydot.Dot()
        dot.set('rankdir', 'TB')
        dot.set('concentrate', True)
        dot.set_node_defaults(shape='record')

        cdef vector[HandCards] opposite_hand_card_combinations
        cdef Observation obs

        if not use_cache:
            table = {}
            for i in range(modelRating.eval_games.size()):
                for start_player in range(2):
                    self.env.set_state(&modelRating.eval_games[i])
                    self.env.current_player = start_player

                    self.env.regenerate_obs(&obs)
                    self.game_tree_step(model, obs, dot, None, 0, 1, 0, "", table, False, 0)
                print(i)


            print("Squashing probs")
            for key in table.keys():
                new_probs = []
                prob_sum = 0
                for card in range(len(table[key][0][1])):
                    result_sum = 0
                    for guess in table[key]:
                        result_sum += guess[0] * guess[1][card]
                    new_probs.append(exp(result_sum))
                    prob_sum += new_probs[-1]
                table[key] = [prob / prob_sum for prob in new_probs]

            with open("tree-cache.pk", 'wb') as handle:
                pickle.dump(table, handle)
        else:
            with open("tree-cache.pk", 'rb') as handle:
                table = pickle.load(handle)

        print("Generating tree")
        self.env.set_state(&modelRating.eval_games[tree_ind])
        self.env.current_player = 0
        self.env.regenerate_obs(&obs)
        self.game_tree_step(model, obs, dot, None, 0, 1, 0, "", table, True, 0)
        png_str = dot.create_png(prog='dot')
        dot.write_svg('tree.svg')

        sio = BytesIO()
        sio.write(png_str)
        sio.seek(0)

        # plot the image
        fig, ax = plt.subplots(figsize=(18, 5))
        ax.imshow(plt.imread(sio), interpolation="bilinear")

    def test(self):
        pass