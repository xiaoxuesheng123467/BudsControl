using System.Windows;

namespace BudsControl.Windows;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _viewModel;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs eventArgs)
    {
        await _viewModel.InitializeAsync();
    }

    private async void Window_Closed(object? sender, EventArgs eventArgs)
    {
        await _viewModel.DisposeAsync();
    }

    private void FindButton_Click(object sender, RoutedEventArgs eventArgs)
    {
        if (!_viewModel.FindActive)
        {
            MessageBoxResult answer = MessageBox.Show(
                this,
                "耳机将以较大音量响铃。请先确认左右耳都没有戴在耳朵里。",
                "开始查找耳机",
                MessageBoxButton.OKCancel,
                MessageBoxImage.Warning,
                MessageBoxResult.Cancel);
            if (answer != MessageBoxResult.OK)
            {
                return;
            }
        }

        if (_viewModel.ToggleFindCommand.CanExecute(null))
        {
            _viewModel.ToggleFindCommand.Execute(null);
        }
    }
}
