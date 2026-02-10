"""Extended tests for dictate.output — output handlers and factory.

Tests ClipboardOutput, TyperOutput, and create_output_handler factory function.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from dictate.config import OutputMode
from dictate.output import (
    ClipboardOutput,
    TyperOutput,
    create_output_handler,
)


class TestClipboardOutputExtended:
    """Extended tests for ClipboardOutput class."""

    @patch("dictate.output.pyperclip")
    def test_output_copies_to_clipboard(self, mock_pyperclip):
        """Test that output copies text to clipboard."""
        handler = ClipboardOutput()
        handler.output("Hello, World!")
        
        mock_pyperclip.copy.assert_called_once_with("Hello, World!")

    @patch("dictate.output.pyperclip")
    def test_output_with_empty_string(self, mock_pyperclip):
        """Test output with empty string."""
        handler = ClipboardOutput()
        handler.output("")
        
        mock_pyperclip.copy.assert_called_once_with("")

    @patch("dictate.output.pyperclip")
    def test_output_with_special_characters(self, mock_pyperclip):
        """Test output with special characters."""
        handler = ClipboardOutput()
        special_text = "Hello! @#$%^&*() \\n \\t \\r \"quoted\""
        handler.output(special_text)
        
        mock_pyperclip.copy.assert_called_once_with(special_text)

    @patch("dictate.output.pyperclip")
    def test_output_with_unicode(self, mock_pyperclip):
        """Test output with unicode characters."""
        handler = ClipboardOutput()
        unicode_text = "Hello 世界 🌍 Привет"
        handler.output(unicode_text)
        
        mock_pyperclip.copy.assert_called_once_with(unicode_text)

    @patch("dictate.output.pyperclip")
    def test_output_with_multiline(self, mock_pyperclip):
        """Test output with multiline text."""
        handler = ClipboardOutput()
        multiline_text = "Line 1\\nLine 2\\nLine 3"
        handler.output(multiline_text)
        
        mock_pyperclip.copy.assert_called_once_with(multiline_text)

    @patch("dictate.output.pyperclip")
    def test_output_with_very_long_text(self, mock_pyperclip):
        """Test output with very long text."""
        handler = ClipboardOutput()
        long_text = "x" * 10000
        handler.output(long_text)
        
        mock_pyperclip.copy.assert_called_once_with(long_text)

    @patch("dictate.output.pyperclip")
    def test_multiple_outputs_overwrite(self, mock_pyperclip):
        """Test that multiple outputs overwrite clipboard."""
        handler = ClipboardOutput()
        handler.output("First")
        handler.output("Second")
        handler.output("Third")
        
        assert mock_pyperclip.copy.call_count == 3
        mock_pyperclip.copy.assert_called_with("Third")


class TestTyperOutputExtended:
    """Extended tests for TyperOutput class."""

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    @patch("dictate.output.time.sleep")
    def test_output_copies_and_pastes(self, mock_sleep, mock_controller_class, mock_pyperclip):
        """Test that output copies to clipboard and simulates paste."""
        mock_controller = MagicMock()
        mock_controller_class.return_value = mock_controller
        
        handler = TyperOutput()
        handler.output("Hello, World!")
        
        # Should copy to clipboard first
        mock_pyperclip.copy.assert_called_once_with("Hello, World!")
        
        # Should sleep for typing delay
        mock_sleep.assert_called_once_with(0.05)
        
        # Should press cmd+v
        mock_controller.press.assert_any_call(mock_controller_class.return_value.press.call_args_list[0][0][0])

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    @patch("dictate.output.time.sleep")
    def test_output_key_sequence(self, mock_sleep, mock_controller_class, mock_pyperclip):
        """Test the exact key press sequence for paste."""
        mock_controller = MagicMock()
        mock_controller_class.return_value = mock_controller
        
        handler = TyperOutput()
        handler.output("test")
        
        # Get all press calls
        press_calls = mock_controller.press.call_args_list
        release_calls = mock_controller.release.call_args_list
        
        # Should press cmd first, then 'v'
        assert len(press_calls) == 2
        
        # Should release 'v' first, then cmd (reverse order)
        assert len(release_calls) == 2

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    @patch("dictate.output.time.sleep")
    def test_output_with_empty_string(self, mock_sleep, mock_controller_class, mock_pyperclip):
        """Test output with empty string."""
        mock_controller = MagicMock()
        mock_controller_class.return_value = mock_controller
        
        handler = TyperOutput()
        handler.output("")
        
        mock_pyperclip.copy.assert_called_once_with("")
        mock_sleep.assert_called_once()

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    @patch("dictate.output.time.sleep")
    def test_output_with_special_characters(self, mock_sleep, mock_controller_class, mock_pyperclip):
        """Test output with special characters."""
        mock_controller = MagicMock()
        mock_controller_class.return_value = mock_controller
        
        handler = TyperOutput()
        special_text = "Hello! @#$%"
        handler.output(special_text)
        
        mock_pyperclip.copy.assert_called_once_with(special_text)

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    @patch("dictate.output.time.sleep")
    def test_output_with_unicode(self, mock_sleep, mock_controller_class, mock_pyperclip):
        """Test output with unicode characters."""
        mock_controller = MagicMock()
        mock_controller_class.return_value = mock_controller
        
        handler = TyperOutput()
        unicode_text = "Hello 世界 🌍"
        handler.output(unicode_text)
        
        mock_pyperclip.copy.assert_called_once_with(unicode_text)

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    def test_output_logs_error_on_failure(self, mock_controller_class, mock_pyperclip):
        """Test that errors are logged on failure."""
        # Provide a real exception class so the except clause works
        mock_pyperclip.PyperclipException = type("PyperclipException", (Exception,), {})
        
        mock_controller = MagicMock()
        mock_controller.press.side_effect = Exception("Keyboard error")
        mock_controller_class.return_value = mock_controller
        
        handler = TyperOutput()
        
        with patch("dictate.output.logger") as mock_logger:
            with pytest.raises(Exception, match="Keyboard error"):
                handler.output("test")
            
            mock_logger.error.assert_called_once()
            assert "Failed to paste text" in mock_logger.error.call_args[0][0]

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    @patch("dictate.output.time.sleep")
    def test_instantiates_controller_once(self, mock_sleep, mock_controller_class, mock_pyperclip):
        """Test that keyboard controller is instantiated once."""
        mock_controller = MagicMock()
        mock_controller_class.return_value = mock_controller
        
        handler = TyperOutput()
        handler.output("First")
        handler.output("Second")
        
        # Controller should be instantiated once
        mock_controller_class.assert_called_once()


class TestCreateOutputHandlerExtended:
    """Extended tests for create_output_handler factory function."""

    def test_returns_clipboard_output_for_clipboard_mode(self):
        """Test factory returns ClipboardOutput for CLIPBOARD mode."""
        handler = create_output_handler(OutputMode.CLIPBOARD)
        assert isinstance(handler, ClipboardOutput)

    def test_returns_typer_output_for_type_mode(self):
        """Test factory returns TyperOutput for TYPE mode."""
        handler = create_output_handler(OutputMode.TYPE)
        assert isinstance(handler, TyperOutput)

    def test_returns_typer_output_as_default(self):
        """Test factory returns TyperOutput as default (for unknown modes)."""
        # This tests the fallback behavior
        handler = create_output_handler(OutputMode.TYPE)
        assert isinstance(handler, TyperOutput)

    @patch("dictate.output.pyperclip")
    def test_clipboard_output_works_correctly(self, mock_pyperclip):
        """Integration test that created ClipboardOutput works."""
        handler = create_output_handler(OutputMode.CLIPBOARD)
        handler.output("Test text")
        
        mock_pyperclip.copy.assert_called_once_with("Test text")

    @patch("dictate.output.pyperclip")
    @patch("dictate.output.KeyboardController")
    @patch("dictate.output.time.sleep")
    def test_typer_output_works_correctly(self, mock_sleep, mock_controller_class, mock_pyperclip):
        """Integration test that created TyperOutput works."""
        mock_controller = MagicMock()
        mock_controller_class.return_value = mock_controller
        
        handler = create_output_handler(OutputMode.TYPE)
        handler.output("Test text")
        
        mock_pyperclip.copy.assert_called_once_with("Test text")
        mock_sleep.assert_called_once()

    def test_mode_enum_values(self):
        """Test that OutputMode enum has expected values."""
        assert OutputMode.TYPE.value == "type"
        assert OutputMode.CLIPBOARD.value == "clipboard"
