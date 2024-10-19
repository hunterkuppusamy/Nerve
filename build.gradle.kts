

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    `maven-publish`
}

group = "dev.hunter"
version = "0.0.16"

kotlin {
    jvm {
        withSourcesJar(publish = false)
    }
    // no reason for these really...
    // linuxX64()
    // mingwX64()

    repositories {
        mavenCentral()
        google()
    }

    sourceSets {
        commonMain {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        jvmMain {
            dependencies {
            }
        }

        linuxMain {
            dependencies {
            }
        }

        mingwMain {
            dependencies {
            }
        }
    }
}

publishing {
    repositories {
        maven {
            // change to point to your repo, e.g. http://my.org/repo
            name = "github"
            url = uri("https://maven.pkg.github.com/hunterkuppusamy/nerve")
            credentials {
                username = "hunterkuppusamy"
                password = System.getenv("TOKEN") ?: System.getenv("GITHUB_TOKEN") ?: project.findProperty("NERVE_PUBLISHING_TOKEN").toString()
            }
        }
    }
    publications {
        create<MavenPublication>("maven") {
            artifactId = project.name.lowercase()
            groupId = project.group.toString().lowercase()
            version = project.version.toString()

            pom {
                name = "Nerve"
                description = "An interpreted language made on Tuesday"
                url = "https://github.com/hunterkuppusamy/nerve"
                developers {
                    developer {
                        id = "hunter"
                        name = "Hunter Kuppusamy"
                        email = "hunterkupp@gmail.com"
                    }
                }
            }

            println("artifact = $group:$artifactId:$version")

            from(getComponents()["kotlin"]) // the property delegate for the function is actually overloaded and idk how to not do that!
        }
    }
}