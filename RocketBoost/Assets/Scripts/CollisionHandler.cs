using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;

// The rules: what happens when the rocket touches something.
// Friendly - safe, Finish - landing (next level), anything else - crash.
// From the book, Part 8.1, with the changes from the ads guide, Part 2.5.
public class CollisionHandler : MonoBehaviour
{
    [SerializeField] float levelLoadDelay = 2f;
    [SerializeField] AudioClip successSFX;
    [SerializeField] AudioClip crashSFX;
    [SerializeField] ParticleSystem successParticles;
    [SerializeField] ParticleSystem crashParticles;

    AudioSource audioSource;

    bool isControllable = true;
    bool isCollidable = true;

    public bool IsCollidable => isCollidable;

    private void Start()
    {
        audioSource = GetComponent<AudioSource>();
    }

    private void Update()
    {
        RespondToDebugKeys();
    }

    void RespondToDebugKeys()
    {
        // Debug keys work only in the editor and in Development builds, so players cannot cheat
        if (!Debug.isDebugBuild) { return; }
        // A phone has no keyboard: Keyboard.current is null
        if (Keyboard.current == null) { return; }

        if (Keyboard.current.lKey.wasPressedThisFrame)
        {
            LoadNextLevel();
        }
        else if (Keyboard.current.cKey.wasPressedThisFrame)
        {
            isCollidable = !isCollidable;
            Debug.Log("Collisions: " + (isCollidable ? "on" : "off"));
        }
    }

    private void OnCollisionEnter(Collision other)
    {
        if (!isControllable || !isCollidable) { return; }

        switch (other.gameObject.tag)
        {
            case "Friendly":
                Debug.Log("Everything is looking good!");
                break;
            case "Finish":
                StartSuccessSequence();
                break;
            default:
                StartCrashSequence();
                break;
        }
    }

    void StartSuccessSequence()
    {
        isControllable = false;
        PlaySound(successSFX);
        if (successParticles != null) successParticles.Play();
        GetComponent<Movement>().enabled = false;
        if (GameManager.Instance != null) GameManager.Instance.Announce("landed");
        Invoke(nameof(LoadNextLevel), levelLoadDelay);
    }

    void StartCrashSequence()
    {
        isControllable = false;
        PlaySound(crashSFX);
        if (crashParticles != null) crashParticles.Play();
        GetComponent<Movement>().enabled = false;

        // We take away a try right away, and we decide what to do after a pause
        if (GameManager.Instance != null)
        {
            GameManager.Instance.RegisterCrash();
            GameManager.Instance.Announce("crashed");
        }
        Invoke(nameof(AfterCrash), levelLoadDelay);
    }

    void PlaySound(AudioClip clip)
    {
        if (audioSource == null) return;
        audioSource.Stop();
        if (clip != null) audioSource.PlayOneShot(clip);
    }

    void AfterCrash()
    {
        if (GameManager.Instance != null)
        {
            // Tries are left: the level reloads. No tries: the Game Over window
            GameManager.Instance.FinishCrash();
        }
        else
        {
            ReloadLevel();
        }
    }

    void LoadNextLevel()
    {
        int currentScene = SceneManager.GetActiveScene().buildIndex;
        int nextScene = currentScene + 1;

        if (nextScene == SceneManager.sceneCountInBuildSettings)
        {
            nextScene = 0; // after the last level we go back to the main menu (scene 0)
        }

        if (GameManager.Instance != null)
        {
            GameManager.Instance.LevelCompleted(nextScene);
        }
        else
        {
            SceneManager.LoadScene(nextScene);
        }
    }

    void ReloadLevel()
    {
        int currentScene = SceneManager.GetActiveScene().buildIndex;
        SceneManager.LoadScene(currentScene);
    }
}
