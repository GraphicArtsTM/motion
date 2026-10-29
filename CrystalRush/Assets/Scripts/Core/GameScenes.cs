using UnityEngine.SceneManagement;

/// <summary>
/// Scene names in one place, so a typo cannot break loading.
/// All of these scenes are added to Build Settings by the setup tool.
/// </summary>
public static class GameScenes
{
    public const string MainMenu = "MainMenu";
    public const int LevelCount = 3;

    // The score is carried from one level to the next during one run.
    public static int CarriedScore;

    public static string Level(int number) => "Level" + number;

    public static void StartNewRun(int level)
    {
        CarriedScore = 0;
        SceneManager.LoadScene(Level(level));
    }
}
