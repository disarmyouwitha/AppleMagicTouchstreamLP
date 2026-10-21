import math
import unittest
from acceleration import CURVE_KEYS, Parametric, compare, fixed, predictions, recording_rows


def config(linear=1, parabolic=0, tangent=0, root=0):
    curve = dict(zip(CURVE_KEYS, [linear, parabolic, 0, 0, tangent, root]))
    return {'resolution': 67, 'algorithm_rate': 67, 'acceleration': 0,
            'fixed_multiplier': 1, 'report_rate': 0, 'curves': [{'index': 0, **curve}]}


class AccelerationTests(unittest.TestCase):
    def test_linear_units_are_96_over_resolution(self):
        cfg = config(); cfg['resolution'] = 400
        model = Parametric(cfg)
        dx, dy, gain = model.delta(1, 3, -4)
        self.assertAlmostEqual(gain, 96/400)
        self.assertAlmostEqual(dx, .72)
        self.assertAlmostEqual(dy, -.96)

    def test_quadratic_parameter_is_squared_not_just_a_coefficient(self):
        model = Parametric(config(linear=1, parabolic=.5))
        # At standardized x=2: y=2+(.5*2)^2=3, NOT 2+.5*2^2=4.
        self.assertAlmostEqual(model.accelerated_velocity(2), 3*96/67)

    def test_polynomial_tangent_and_root_hand_calculated_vectors(self):
        model = Parametric(config(linear=1, parabolic=.5, tangent=2, root=4))
        # f(x)=x+.25x²; f(2)=3; tangent 2x-1; root sqrt(28x-63).
        for x, y in [(1,1.25),(2,3),(3,5),(4,7),(5,math.sqrt(77))]:
            self.assertAlmostEqual(model.accelerated_velocity(x), y*96/67)
        for boundary in [2,4]:
            self.assertAlmostEqual(model.accelerated_velocity(boundary-1e-8),
                                   model.accelerated_velocity(boundary+1e-8), places=6)

    def test_curve_interpolation_and_high_low_clamp(self):
        cfg = config()
        cfg['curves'].append({**cfg['curves'][0], 'index': 2, 'HIDAccelGainLinear': 3})
        self.assertEqual(Parametric(cfg, acceleration=1).linear, 2)
        self.assertEqual(Parametric(cfg, acceleration=5).linear, 3)
        cfg['curves'][0]['index'] = .5
        self.assertEqual(Parametric(cfg, acceleration=0).linear, 1)

    def test_disabled_acceleration_is_passthrough(self):
        self.assertEqual(Parametric(config(), acceleration=-1).delta(1,2,-3), (2,-3,1))

    def test_time_normalization_only_when_fixed_multiplier_is_one(self):
        cfg = config(parabolic=.5); cfg['report_rate'] = 100
        regular, slow = Parametric(cfg), Parametric(cfg)
        regular.delta(1,2,0); slow.delta(1,2,0)
        self.assertGreater(regular.delta(1.01,2,0)[0], slow.delta(1.02,2,0)[0])
        cfg['fixed_multiplier'] = .75
        a,b = Parametric(cfg),Parametric(cfg)
        a.delta(1,2,0); b.delta(1,2,0)
        self.assertEqual(a.delta(1.01,2,0), b.delta(1.02,2,0))

    def test_zero_displacement_stays_zero_and_subpixel_input_is_finite(self):
        model = Parametric(config(parabolic=.5))
        self.assertEqual(model.delta(1,0,0)[:2], (0,0))
        self.assertTrue(all(math.isfinite(x) for x in model.delta(2,.01,-.01)))

    def test_bad_time_and_nonfinite_data_are_rejected(self):
        model = Parametric(config())
        model.delta(1,1,0)
        with self.assertRaises(ValueError): model.delta(1,1,0)
        with self.assertRaises(ValueError): model.delta(2,float('nan'),0)

    def test_mm_requires_explicit_unproven_contact_to_count_scale(self):
        rows = [{'t':1,'dx':1,'dy':0}]
        with self.assertRaises(ValueError): list(predictions(rows,config(),units='mm'))
        result = list(predictions(rows,config(),units='mm',counts_per_mm=2))[0]
        self.assertAlmostEqual(result['predicted_dx'], 2*96/67)

    def test_comparison_reports_vector_and_segment_endpoint_errors(self):
        result = compare([{'predicted_dx':4,'predicted_dy':6,'native_dx':1,'native_dy':2}])
        self.assertEqual(result['vector_rmse_points'], 5)
        self.assertEqual(result['segments']['0']['endpoint_error_points'], 5)

    def recording(self):
        result = [{'schema':'gesturepad.pointer-recording.v1'}]
        result += [{'kind':'pointer','t':i*.01,'x':i,'y':0} for i in range(5)]
        result += [{'kind':'contacts','t':i*.01,'contacts':[{'id':1,'state':4,'x':i*.1,'y':.5}]} for i in range(1,4)]
        return result

    def test_recording_alignment_uses_one_finger_and_resets_on_other_contacts(self):
        rows = list(recording_rows(self.recording(),100,100))
        self.assertEqual(len(rows),2)
        self.assertAlmostEqual(rows[0]['dx'],10)
        self.assertAlmostEqual(rows[0]['native_dx'],1)
        records = self.recording()
        records[-2]['contacts'].append({'id':2,'state':4,'x':.3,'y':.5})
        self.assertEqual(list(recording_rows(records,100,100)),[])

    def test_bad_recordings_are_rejected_instead_of_scoring_incomplete_samples(self):
        for key in ['tap_disabled','dropped_contacts','stop_result']:
            records = self.recording(); records[0][key] = 1
            with self.assertRaises(ValueError): list(recording_rows(records,100,100))

    def test_screen_edge_and_large_pointer_gaps_are_excluded(self):
        records = self.recording()
        for r in records[1:6]: r['edge'] = True
        self.assertEqual(list(recording_rows(records,100,100)),[])

    def test_fixed_point_sign_conversion(self):
        self.assertEqual(fixed(196608),3)
        self.assertEqual(fixed(0xffff0000),-1)


if __name__ == '__main__': unittest.main()
