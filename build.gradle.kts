plugins {
    `maven-publish`
    kotlin("jvm") version "2.0.0"
    id("io.github.goooler.shadow") version "8.1.2"
}

group = "dev.hunter"
version = "0.1.1"

repositories {
    mavenCentral()
    google()
}

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.asm)
}

kotlin {
    jvmToolchain(21)
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

            from(components["kotlin"])
            // from(getComponents()["kotlin"]) // the property delegate for the function is actually overloaded and idk how to not do that!
        }
    }
}