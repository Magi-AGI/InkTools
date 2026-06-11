using UnityEngine;

namespace Magi.InkTools.ITUMS
{
    [CreateAssetMenu(fileName = "PersonaConfig", menuName = "Inkling/ITUMS/Persona Config", order = 0)]
    public class PersonaConfig : ScriptableObject
    {
        [Header("Evaluation Window (seconds)")]
        public float evaluationPeriodSeconds = 20f;

        [Header("Quiet Thresholds")]
        [Tooltip("Idle time accumulated within the evaluation window to classify as Quiet.")]
        public float quietSecondsThreshold = 12f;

        [Header("Aggressive Thresholds")]
        [Tooltip("Average stroke speed (units/sec) within the evaluation window to classify as Aggressive.")]
        public float aggressiveSpeedThreshold = 0.35f;

        [Header("Defaults")]
        public Persona defaultPersona = Persona.Normal;
    }
}
