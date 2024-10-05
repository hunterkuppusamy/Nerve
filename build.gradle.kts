import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.jetbrainsCompose)
    alias(libs.plugins.compose.compiler)
    `maven-publish`
}

group = "dev.hunter.nerve"
version = "0.0.1"

repositories {
    mavenCentral()
    google()
}

kotlin {
    jvm()
    linuxX64()
    mingwX64()

    sourceSets {
        commonMain {
            dependencies {
                implementation(compose.foundation)
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        jvmMain {
            dependencies {

            }
        }

        linuxMain {
            dependencies {
                implementation(compose.desktop.linux_x64)
            }
        }

        mingwMain {
            dependencies {
                implementation(compose.desktop.windows_x64)
            }
        }
    }
}

compose.desktop {
    application {
        mainClass = "dev.hunter.nerve.MainKt"

        nativeDistributions {
            targetFormats(TargetFormat.Exe, TargetFormat.Deb)
            packageName = "dev.hunter.nerve"
            packageVersion = "0.0.1"
        }
    }
}

tasks {
    publish {
        publishing {
            repositories {
                maven {
                    // change to point to your repo, e.g. http://my.org/repo
                    name = "github"
                    url = uri("https://maven.pkg.github.com/hunterkuppusamy/Nerve")
                    credentials {
                        username = "hunterkuppusamy"
                        password = System.getenv("TOKEN") ?: System.getenv("GITHUB_TOKEN") ?: project.findProperty("NERVE_PUBLISHING_TOKEN").toString()
                    }
                }
            }
            publications {
                create<MavenPublication>("Nerve") {
                    pom {
                        name = "Nerve"
                        description = "An interpreted language made on Tuesday"
                        url = "https://github.com/hunterkuppusamy/Nerve"
                        developers {
                            developer {
                                id = "hunter"
                                name = "Hunter Kuppusamy"
                                email = "hunterkupp@gmail.com"
                            }
                        }
                    }
                    groupId = project.group.toString()
                    artifactId = project.name.lowercase()
                    version = project.version.toString()
                }
            }
        }
    }
}
