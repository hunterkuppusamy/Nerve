package dev.hunter.nerve

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.text.selection.DisableSelection
import androidx.compose.material.Button
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.window.MenuBar
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import javax.swing.LayoutStyle

actual val platform: Platform = object: Platform {
    override val name: String= "JVM@${System.getenv("JAVA_HOME")}"
    override val logger: Logger = object: Logger {
        override fun info(message: String) = println(message)
        override fun warning(message: String) = println("WARNING: $message")
        override fun error(message: String) = println("ERROR: $message")
    }
    override val entry: () -> Unit = {
        application {
            Window(
                onCloseRequest = ::exitApplication,
                title = "Nerve Interpreter"
            ){
                Box(
                    contentAlignment = Alignment.BottomCenter
                ) {
                    Button(
                        content = {
                            Text("Hea")
                        },
                        onClick = {
                            println("Hello Interpreter")
                        }
                    )
                }
            }
        }
    }
}