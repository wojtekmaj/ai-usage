using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace AiUsage.Windows;

internal static class Program
{
    private const string InstanceMutexName = "Local\\AiUsage.Windows.Instance";
    private const string ActivationEventName = "Local\\AiUsage.Windows.Activate";
    private static int activationPending;

    [STAThread]
    private static void Main(string[] args)
    {
        using var activationEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ActivationEventName);
        using var instanceMutex = new Mutex(true, InstanceMutexName, out var isFirstInstance);
        if (!isFirstInstance)
        {
            activationEvent.Set();
            return;
        }

        WinRT.ComWrappersSupport.InitializeComWrappers();
        var waitRegistration = ThreadPool.RegisterWaitForSingleObject(
            activationEvent,
            (_, _) => RequestActivation(),
            null,
            Timeout.Infinite,
            executeOnlyOnce: false);

        try
        {
            Application.Start(_unused =>
            {
                var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                _ = new App();
            });
        }
        finally
        {
            waitRegistration.Unregister(null);
            instanceMutex.ReleaseMutex();
        }
    }

    internal static void DeliverPendingActivation(App app)
    {
        if (Interlocked.Exchange(ref activationPending, 0) != 0)
        {
            app.HandleRedirectedActivation();
        }
    }

    private static void RequestActivation()
    {
        if (Application.Current is App app)
        {
            app.HandleRedirectedActivation();
        }
        else
        {
            Interlocked.Exchange(ref activationPending, 1);
        }
    }
}
