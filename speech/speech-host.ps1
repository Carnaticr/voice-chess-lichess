# Speech host for the Lichess voice client.
# Talks JSON lines over stdin/stdout with the Electron main process.
# Uses the Windows built-in System.Speech engine (offline, no API keys).
#
# stdin commands:
#   {"type":"grammar","items":[{"phrase":"knight f three","value":"g1f3"}, ...]}
#   {"type":"listen","on":true}
#   {"type":"say","text":"Knight takes e 5"}
#   {"type":"voice","name":"Microsoft Zira Desktop","rate":0}
#   {"type":"threshold","value":0.6}
# stdout events:
#   ready, heard, rejected, speechDetected, listening, speaking, error

$ErrorActionPreference = 'Stop'

$source = @"
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Speech.Recognition;
using System.Speech.Synthesis;
using System.Threading;
using System.Web.Script.Serialization;

public static class ChessSpeechHost
{
    static readonly object outLock = new object();
    static readonly JavaScriptSerializer json = new JavaScriptSerializer();
    static SpeechRecognitionEngine rec;
    static SpeechSynthesizer tts;
    static bool wantListening = false;
    static bool recRunning = false;
    static bool stopPending = false;
    static volatile bool speaking = false;
    static DateTime speechEndedAt = DateTime.MinValue;
    static double threshold = 0.6;
    static Grammar currentGrammar;

    static void Emit(Dictionary<string, object> msg)
    {
        string line = json.Serialize(msg);
        lock (outLock)
        {
            Console.Out.WriteLine(line);
            Console.Out.Flush();
        }
    }

    static Dictionary<string, object> Msg(string type)
    {
        var d = new Dictionary<string, object>();
        d["type"] = type;
        return d;
    }

    static void Error(string message)
    {
        var m = Msg("error");
        m["message"] = message;
        Emit(m);
    }

    public static void Run()
    {
        Console.InputEncoding = System.Text.Encoding.UTF8;
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);

        tts = new SpeechSynthesizer();
        tts.SetOutputToDefaultAudioDevice();
        tts.SpeakStarted += delegate { speaking = true; EmitSpeaking(true); };
        tts.SpeakCompleted += delegate
        {
            if (tts.State != SynthesizerState.Speaking)
            {
                speaking = false;
                speechEndedAt = DateTime.UtcNow;
                EmitSpeaking(false);
            }
        };

        string recognizerName = null;
        try
        {
            RecognizerInfo info = null;
            foreach (var r in SpeechRecognitionEngine.InstalledRecognizers())
            {
                if (r.Culture.TwoLetterISOLanguageName == "en") { info = r; break; }
            }
            if (info == null)
            {
                var all = SpeechRecognitionEngine.InstalledRecognizers();
                if (all.Count > 0) info = all[0];
            }
            if (info == null) throw new Exception("No Windows speech recognizer is installed. Install the English speech pack in Settings > Time & language > Speech.");
            rec = new SpeechRecognitionEngine(info);
            recognizerName = info.Name + " (" + info.Culture.Name + ")";
            TryInitMic();
            rec.SpeechRecognized += OnRecognized;
            rec.SpeechRecognitionRejected += OnRejected;
            rec.SpeechDetected += delegate { if (!speaking) Emit(Msg("speechDetected")); };
            rec.RecognizeCompleted += delegate { recRunning = false; stopPending = false; };
            // Be a bit snappier than the defaults.
            rec.EndSilenceTimeout = TimeSpan.FromMilliseconds(500);
            // When what was said so far could still be the start of a longer move ("knight b ..."),
            // wait longer so a pause doesn't force-match a shorter, wrong phrase.
            rec.EndSilenceTimeoutAmbiguous = TimeSpan.FromMilliseconds(1100);
            rec.MaxAlternates = 5;
            LoadItems(new List<KeyValuePair<string, string>>());
        }
        catch (Exception ex)
        {
            rec = null;
            Error("Speech recognition unavailable: " + ex.Message);
        }

        var ready = Msg("ready");
        ready["recognizer"] = recognizerName;
        ready["voices"] = tts.GetInstalledVoices().Where(v => v.Enabled).Select(v => v.VoiceInfo.Name).ToArray();
        Emit(ready);

        string line;
        while ((line = Console.In.ReadLine()) != null)
        {
            line = line.Trim();
            if (line.Length == 0) continue;
            try { Handle(json.Deserialize<Dictionary<string, object>>(line)); }
            catch (Exception ex) { Error(ex.Message); }
        }
        StopRec();
    }

    static bool micReady = false;

    static bool TryInitMic()
    {
        if (micReady) return true;
        try { rec.SetInputToDefaultAudioDevice(); micReady = true; }
        catch (Exception) { Error("No microphone found. Connect a microphone and allow desktop apps to use it (Settings > Privacy & security > Microphone)."); }
        return micReady;
    }

    static void EmitSpeaking(bool on)
    {
        var m = Msg("speaking");
        m["on"] = on;
        Emit(m);
    }

    static void Handle(Dictionary<string, object> cmd)
    {
        string type = cmd.ContainsKey("type") ? (string)cmd["type"] : "";
        switch (type)
        {
            case "say":
            {
                string text = (string)cmd["text"];
                if (cmd.ContainsKey("interrupt") && (bool)cmd["interrupt"]) tts.SpeakAsyncCancelAll();
                speaking = true;
                tts.SpeakAsync(text);
                break;
            }
            case "voice":
            {
                if (cmd.ContainsKey("name") && cmd["name"] != null && ((string)cmd["name"]).Length > 0)
                {
                    try { tts.SelectVoice((string)cmd["name"]); } catch (Exception ex) { Error("Voice: " + ex.Message); }
                }
                if (cmd.ContainsKey("rate") && cmd["rate"] != null) tts.Rate = Math.Max(-10, Math.Min(10, Convert.ToInt32(cmd["rate"])));
                if (cmd.ContainsKey("volume") && cmd["volume"] != null) tts.Volume = Math.Max(0, Math.Min(100, Convert.ToInt32(cmd["volume"])));
                break;
            }
            case "threshold":
                threshold = Convert.ToDouble(cmd["value"], CultureInfo.InvariantCulture);
                break;
            case "grammar":
            {
                var items = new List<KeyValuePair<string, string>>();
                var arr = cmd["items"] as System.Collections.ArrayList;
                if (arr != null)
                {
                    foreach (var o in arr)
                    {
                        var d = o as Dictionary<string, object>;
                        if (d == null) continue;
                        items.Add(new KeyValuePair<string, string>((string)d["phrase"], (string)d["value"]));
                    }
                }
                LoadItems(items);
                break;
            }
            case "listen":
            {
                wantListening = (bool)cmd["on"];
                if (wantListening) StartRec(); else StopRec();
                break;
            }
            case "testWav":
            {
                // Debug helper: recognize from a WAV file instead of the microphone.
                if (rec == null) break;
                if (recRunning) { rec.RecognizeAsyncCancel(); WaitStopped(); }
                rec.SetInputToWaveFile((string)cmd["path"]);
                micReady = false;
                var res = rec.Recognize();
                var m = res == null ? Msg("testResult") : Describe(res, "testResult");
                Emit(m);
                rec.SetInputToNull();
                break;
            }
            case "quit":
                Environment.Exit(0);
                break;
        }
    }

    static void LoadItems(List<KeyValuePair<string, string>> items)
    {
        if (rec == null) return;
        var choices = new Choices();
        int count = 0;
        var seen = new HashSet<string>();
        foreach (var kv in items)
        {
            string phrase = kv.Key.Trim().ToLowerInvariant();
            if (phrase.Length == 0 || !seen.Add(phrase)) continue;
            choices.Add(new SemanticResultValue(phrase, kv.Value));
            count++;
        }
        if (count == 0) choices.Add(new SemanticResultValue("nothing to do", "noop"));

        var gb = new GrammarBuilder();
        gb.Culture = rec.RecognizerInfo.Culture;
        gb.Append(new SemanticResultKey("value", choices));
        // Allow people to say "check" / "mate" after a move; ignored semantically.
        gb.Append(new Choices("check", "checkmate", "mate"), 0, 1);
        var g = new Grammar(gb);
        g.Name = "moves";

        bool wasRunning = recRunning;
        if (wasRunning) { rec.RecognizeAsyncCancel(); WaitStopped(); }
        if (currentGrammar != null) rec.UnloadGrammar(currentGrammar);
        rec.LoadGrammar(g);
        currentGrammar = g;
        if (wasRunning || (wantListening && micReady)) StartRec();

        var m = Msg("grammarLoaded");
        m["count"] = count;
        Emit(m);
    }

    static void WaitStopped()
    {
        for (int i = 0; i < 100 && recRunning; i++) Thread.Sleep(10);
        recRunning = false;
    }

    static void StartRec()
    {
        if (rec == null) { EmitListening(); return; }
        if (recRunning)
        {
            if (!stopPending) { EmitListening(); return; }
            // A graceful stop is still finishing; cancel it and start fresh.
            rec.RecognizeAsyncCancel();
            WaitStopped();
        }
        if (!TryInitMic()) { wantListening = false; EmitListening(); return; }
        try
        {
            rec.RecognizeAsync(RecognizeMode.Multiple);
            recRunning = true;
            stopPending = false;
        }
        catch (Exception ex) { Error("Mic: " + ex.Message); }
        EmitListening();
    }

    static void StopRec()
    {
        // Stop (not cancel) so a phrase already being spoken still completes (push-to-talk release).
        if (rec != null && recRunning && !stopPending) { stopPending = true; rec.RecognizeAsyncStop(); }
        EmitListening();
    }

    static void EmitListening()
    {
        var m = Msg("listening");
        m["on"] = wantListening && rec != null && micReady;
        m["available"] = rec != null;
        Emit(m);
    }

    static bool HeardOwnVoice(RecognitionResult r)
    {
        // Ignore anything captured while we were talking (the mic hears the speakers).
        if (speaking) return true;
        if (r.Audio != null)
        {
            DateTime startUtc = r.Audio.StartTime.ToUniversalTime();
            if (startUtc < speechEndedAt.AddMilliseconds(150)) return true;
        }
        return false;
    }

    static void OnRecognized(object sender, SpeechRecognizedEventArgs e)
    {
        var r = e.Result;
        if (HeardOwnVoice(r)) return;
        Emit(Describe(r, r.Confidence >= threshold ? "heard" : "rejected"));
    }

    static string ValueOf(RecognizedPhrase p)
    {
        return p.Semantics != null && p.Semantics.ContainsKey("value") ? p.Semantics["value"].Value as string : null;
    }

    // Result plus the best competing interpretations that mean something different,
    // so the app can ask instead of guessing when two moves sounded alike.
    static Dictionary<string, object> Describe(RecognitionResult r, string type)
    {
        var m = Msg(type);
        string value = ValueOf(r);
        m["text"] = r.Text;
        m["value"] = value;
        m["confidence"] = Math.Round(r.Confidence, 3);
        var alts = new List<Dictionary<string, object>>();
        var seen = new HashSet<string>();
        if (value != null) seen.Add(value);
        if (r.Alternates != null)
        {
            foreach (var a in r.Alternates)
            {
                string v = ValueOf(a);
                if (v == null || !seen.Add(v)) continue;
                var d = new Dictionary<string, object>();
                d["text"] = a.Text;
                d["value"] = v;
                d["confidence"] = Math.Round(a.Confidence, 3);
                alts.Add(d);
                if (alts.Count >= 3) break;
            }
        }
        m["alternates"] = alts;
        return m;
    }

    static void OnRejected(object sender, SpeechRecognitionRejectedEventArgs e)
    {
        var r = e.Result;
        if (r == null || HeardOwnVoice(r)) return;
        var m = Msg("rejected");
        m["text"] = r.Text;
        m["value"] = null;
        m["confidence"] = Math.Round(r.Confidence, 3);
        Emit(m);
    }
}
"@

try {
    Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies @('System.Speech', 'System.Web.Extensions', 'System.Core') | Out-Null
    [ChessSpeechHost]::Run()
} catch {
    $err = @{ type = 'error'; message = "Speech host failed: $($_.Exception.Message)" } | ConvertTo-Json -Compress
    [Console]::Out.WriteLine($err)
    exit 1
}
