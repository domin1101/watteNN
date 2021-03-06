import pickle
from pathlib import Path

import tensorflow as tf
import time

import taskplan

from src.Storage import Storage
from src.MCTS import MCTS
from src.LookUp import LookUp
from src.KerasModel import KerasModel
from src.Game import Game
from src.ModelRating import ModelRating
from gym_watten.envs.watten_env import WattenEnv
import time as pytime

from src.XorShfGenerator import XorShfGenerator


class WatteNNTask(taskplan.Task):

    def __init__(self, config, logger, metadata):
        super().__init__(config, logger, metadata)
        self.sum = 0
        self.env = WattenEnv(self.config.get_bool("minimal_env"))
        self.model = self._build_model()
        self.best_model = self._build_model()
        self.train_model = self._build_model()
        self.storage = Storage(self.config.get_int("storage_size"))
        self.rng = XorShfGenerator()
        self.mcts = MCTS(self.rng, self.config.get_int("episodes"), self.config.get_int("mcts_sims"), exploration=self.config.get_float("exploration"), step_exploration=self.config.get_float("step_exploration"))
        self.game = Game(self.env)
        self.train_model.copy_weights_from(self.model)
        self.best_model.copy_weights_from(self.model)
        self.rating = ModelRating(self.env)

    def _build_model(self):
        if self.config.get_string('model_type') == 'network':
            return KerasModel(self.env, self.config.get_int("hidden_neurons"), self.config.get_int("batch_size"), self.config.get_float("policy_lr"), self.config.get_float("policy_momentum"), self.config.get_float("value_lr"), self.config.get_float("value_momentum"), self.config.get_float("clip"), self.config.get_float("equalizer"))
        else:
            return LookUp(self.config.get_float("clip"), self.config.get_float("policy_lr"))

    def save(self, path):
        self.best_model.save(str(path / Path('best-model')))
        self.train_model.save(str(path / Path('train-model')))
        self.model.save(str(path / Path('model')))

    def step(self, tensorboard_writer, current_iteration):
        start = pytime.time()
        self.mcts.mcts_generate(self.env, self.model, self.storage, self.rating)
        print("1", pytime.time() - start)

        start = pytime.time()
        loss = self.train_model.memorize_storage(self.storage, self.config.get_bool('clear_samples_after_epoch'), self.config.get_int('epochs'), self.config.get_int('sample_size'))
        print("2", pytime.time() - start)
        if loss[0] > 0.5:
            raise ArithmeticError()

        tensorboard_writer.add_summary(tf.Summary(value=[
            tf.Summary.Value(tag="loss_play", simple_value=loss[0]),
            tf.Summary.Value(tag="loss_value", simple_value=loss[1]),
            tf.Summary.Value(tag="loss_choose", simple_value=loss[2])
        ]), current_iteration)

        self.model.copy_weights_from(self.train_model)
        if False and current_iteration % 1 == 0:
            self.model.copy_weights_from(self.train_model)

            rating_value = self.game.compare_rand_games(self.model, self.best_model, 500)
            tensorboard_writer.add_summary(tf.Summary(value=[
                tf.Summary.Value(tag="mean_game_length", simple_value=self.game.mean_game_length),
                tf.Summary.Value(tag="win_rate", simple_value=rating_value),
                tf.Summary.Value(tag="mean_v_p1", simple_value=self.game.mean_v_p1)
            ]), current_iteration)

            if rating_value > 0.52:
                self.best_model.copy_weights_from(self.model)

        if self.config.get_bool("minimal_env") and current_iteration % self.config.get_int("exploit_interval") == 0:
            self.best_model.copy_weights_from(self.model)
            table, avg_diff_on, avg_diff_off, max_diff, v_loss_on, v_loss_off, v_based_avg_diff_on, v_based_avg_diff_off = self.game.draw_game_tree(self.best_model, self.rating, False, None, None, "trees/" + str(current_iteration) + ".svg")

            tensorboard_writer.add_summary(tf.Summary(value=[
                tf.Summary.Value(tag="pbe/on", simple_value=avg_diff_on),
                tf.Summary.Value(tag="pbe/off", simple_value=avg_diff_off),
                tf.Summary.Value(tag="true_loss/v/on", simple_value=v_loss_on),
                tf.Summary.Value(tag="true_loss/v/off", simple_value=v_loss_off),
                tf.Summary.Value(tag="true_loss/pbe/on", simple_value=v_based_avg_diff_on),
                tf.Summary.Value(tag="true_loss/pbe/off", simple_value=v_based_avg_diff_off)
            ]), current_iteration)

    def load(self, path):
        self.best_model.load(str(path / Path('best-model')))
        self.train_model.load(str(path / Path('train-model')))
        self.model.load(str(path / Path('model')))