pragma circom 2.0.0;


/**
 * Checks that the evaluations of composition polynomials sent by the prover
 * are consistent with valuations obtained by evaluating constraints over the
 * out-of-domain frame. This template does not return any signal, its purpose is
 * just to create the 'channel_result === evaluation_result' constraint
 *
 * ARGUMENTS:
 * - See verify.circom
 *
 * INPUTS:
 * - boundary_coeffs: Fiat-Shamir coefficients for the boundary constraints.
 * - channel_ood_evaluations: Out Of Domain evaluations given in the proof.
 * - frame: the Out Of Domain frame over which the constraints will be evaluated.
 * - public_inputs: inputs used for the calculation
 * - transition_coeffs: Fiat-Shamir coefficients for the transition constraints.
 * - z: Out Of Domain point of evaluation, generated in the public coin.
 *
 * TODO:
 * - add support for composition with different degrees
 * - add support for periodic values
 * - group transitions by degree to reduce the number of degree adjustment
 */
template OodConsistencyCheck(
    ce_blowup_factor,
    num_assertions,
    num_public_inputs,
    trace_length,
    trace_width
) {
    signal input boundary_coeffs[num_assertions][2];
    signal input channel_ood_evaluations[trace_width];
    signal input frame[2][trace_width];
    signal input ood_frame_constraint_evaluation[trace_width];
    signal input g_trace;
    signal input public_inputs[num_public_inputs];
    signal input transition_coeffs[trace_width][2];
    signal input z;

    signal boundary_temp[num_assertions];
    signal boundary_temp_2[num_assertions];
    signal channel_ood_pow[trace_width];
    signal evaluation_result[trace_width + num_assertions];
    signal transition_divisor;
    signal transition_result;
    signal transition_temp[trace_width];

    component AIR;
    component boundary_deg_adjustment[num_assertions];
    component evaluate_boundary_constraints;
    component gpstep[num_assertions];
    component gp_trace_len;
    component transition_deg_adjustment[trace_width];
    component xpn;



    // BUILDING TRANSITION DIVISOR
    // for transition constraints, it is always the same : div(x) = (x**n)/(product i : 1 --> k : (x - g ** (n - i)))
    // The above divisor specifies that transition constraints must hold on all steps of the execution trace except for the last k steps.
    // The default value for k is 1, n represent the trace length

    gp_trace_len = Pow(trace_length - 1);
    gp_trace_len.in <== g_trace;

    xpn = Pow(trace_length);
    xpn.in <== z;
    transition_divisor <-- (xpn.out - 1) / (z - gp_trace_len.out);
    transition_divisor * (z - gp_trace_len.out) === xpn.out - 1;

    AIR = AIRTransitions(trace_width);
    for (var i = 0; i < trace_width; i++) {
        transition_deg_adjustment[i] = Pow_signal(numbits(trace_length * ce_blowup_factor - 1));
        transition_deg_adjustment[i].in <== z;
        transition_deg_adjustment[i].exp <== trace_length * ce_blowup_factor - AIR.transition_degree[i];
        transition_temp[i] <== transition_coeffs[i][0] + transition_coeffs[i][1] * transition_deg_adjustment[i].out;

        if (i == 0) {
            evaluation_result[i] <== transition_temp[i] * ood_frame_constraint_evaluation[i];
        } else {
            evaluation_result[i] <== evaluation_result[i-1] +  transition_temp[i] * ood_frame_constraint_evaluation[i];
        }

    }

    transition_result <-- evaluation_result[trace_width - 1] / transition_divisor;
    transition_result * transition_divisor ===  evaluation_result[trace_width - 1];


    // BOUNDARY CONSTRAINTS EVALUATIONS

    evaluate_boundary_constraints = AIRAssertions(
        num_assertions,
        num_public_inputs,
        trace_length,
        trace_width
    );

    evaluate_boundary_constraints.g_trace <== g_trace;
    evaluate_boundary_constraints.z <== z;

    for (var i = 0; i < num_public_inputs; i++) {
        evaluate_boundary_constraints.public_inputs[i] <== public_inputs[i];
    }
    for (var i = 0; i < 2; i++){
        for (var j = 0; j < trace_width; j++) {
            evaluate_boundary_constraints.frame[i][j] <== frame[i][j];
        }
    }


    for (var i = 0; i < num_assertions; i++) {
        boundary_deg_adjustment[i] = Pow_signal(255);
        boundary_deg_adjustment[i].in <== z;
        boundary_deg_adjustment[i].exp <== trace_length * ce_blowup_factor -1 + evaluate_boundary_constraints.divisor_degree[i] - (trace_length - 1);
        boundary_temp[i] <==  boundary_coeffs[i][0] + boundary_coeffs[i][1] * boundary_deg_adjustment[i].out;

        // divisor for boundary constraints
        // for single constraints the divisor is always x - g**step
        gpstep[i] = Pow_signal(numbits(trace_length));
        gpstep[i].in <== g_trace;
        gpstep[i].exp <== evaluate_boundary_constraints.step[i];

        if (i == 0) {
            boundary_temp_2[i] <== boundary_temp[i] * evaluate_boundary_constraints.out[i];
            evaluation_result[i + trace_width] <-- transition_result + boundary_temp_2[i] / (z - gpstep[i].out);
            (evaluation_result[i + trace_width] - transition_result)* (z - gpstep[i].out) === boundary_temp_2[i];
        } else {
            boundary_temp_2[i] <== boundary_temp[i] * evaluate_boundary_constraints.out[i];
            evaluation_result[i + trace_width] <-- evaluation_result[i + trace_width -1] +  boundary_temp_2[i] / (z - gpstep[i].out);
            (evaluation_result[i + trace_width] - evaluation_result[i + trace_width -1])* (z - gpstep[i].out) === boundary_temp_2[i];
        }

    }


    // reduce evaluations of composition polynomial columns sent by the prover into
    // a single value by computing sum(z^i * value_i), where value_i is the evaluation of the ith
    // column polynomial at z^m, where m is the total number of column polynomials

    channel_ood_pow[0] <== 1;
    var channel_result = channel_ood_evaluations[0];
    for (var i = 1; i < trace_width; i++) {
        channel_ood_pow[i] <== z * channel_ood_pow[i-1];
        channel_result += channel_ood_evaluations[i] * channel_ood_pow[i];
    }

    channel_result === evaluation_result[trace_width + num_assertions - 1];
}