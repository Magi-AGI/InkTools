using UnityEngine;

namespace Magi.InkTools.ITUMS
{
    public enum Persona
    {
        Normal,
        Quiet,
        Aggressive
    }

    public interface IPersonaService
    {
        Persona CurrentPersona { get; }
        float QuietScore { get; }
        float AggressiveScore { get; }
        void RecordIdle(float deltaSeconds);
        void RecordStrokeSpeed(float speed);
        event PersonaChanged OnPersonaChanged;
    }

    public delegate void PersonaChanged(Persona previous, Persona current, float quietScore, float aggressiveScore);

    /// <summary>
    /// Tracks player behavior samples (idle time, stroke speed) and derives an adaptive persona.
    /// Pure ITUMS logic: no dependency on Inkling services. Consumers can subscribe to persona changes and provide logging/telemetry externally.
    /// </summary>
    public class PersonaService : MonoBehaviour, IPersonaService
    {
        [SerializeField] protected PersonaConfig config;

        private float idleSeconds;
        private float strokeSpeedSum;
        private int strokeSamples;
        private float evalTimer;

        public Persona CurrentPersona { get; private set; } = Persona.Normal;
        public float QuietScore => idleSeconds;
        public float AggressiveScore => strokeSamples > 0 ? strokeSpeedSum / strokeSamples : 0f;

        public event PersonaChanged OnPersonaChanged;

        protected virtual void Awake()
        {
            if (config == null)
            {
                config = ScriptableObject.CreateInstance<PersonaConfig>();
            }
            CurrentPersona = config.defaultPersona;
        }

        protected virtual void Update()
        {
            evalTimer += Time.deltaTime;
            if (config == null || evalTimer < config.evaluationPeriodSeconds)
                return;

            EvaluatePersona();
        }

        public void RecordIdle(float deltaSeconds)
        {
            if (deltaSeconds <= 0f) return;
            idleSeconds += deltaSeconds;
        }

        public void RecordStrokeSpeed(float speed)
        {
            if (speed <= 0f) return;
            strokeSpeedSum += speed;
            strokeSamples++;
        }

        protected virtual void EvaluatePersona()
        {
            Persona next = config.defaultPersona;
            if (idleSeconds >= config.quietSecondsThreshold)
            {
                next = Persona.Quiet;
            }
            else if (AggressiveScore >= config.aggressiveSpeedThreshold)
            {
                next = Persona.Aggressive;
            }

            if (next != CurrentPersona)
            {
                var previous = CurrentPersona;
                CurrentPersona = next;
                OnPersonaChanged?.Invoke(previous, CurrentPersona, idleSeconds, AggressiveScore);
            }

            idleSeconds = 0f;
            strokeSpeedSum = 0f;
            strokeSamples = 0;
            evalTimer = 0f;
        }
    }
}

