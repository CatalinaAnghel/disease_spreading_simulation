/**
* Name: ebola_spreading_model
* Based on the tutorials provided by GAMA Platform: Luneray's Flu and Road Traffic
* Author: Florina-Catalina Anghel
* Tags: ebola spreading, simulation, mortality rates, symptoms, healthcare
*/
model ebola_spreading_model

global {
// simulation settings:
	bool ebola_epidemic <- false; // if the population is aware of the epidemic
	int nb_people <- 700;
	int nb_infected_init <- 50;
	float step <- 5 #mn;
	float travel_probability <- 0.05;

	// population:
	int nb_people_under_17 <- 0 update: people count (each.age <= 17);
	int nb_people_under_29 <- 0 update: people count (each.age <= 29 and each.age > 17);
	int nb_people_under_39 <- 0 update: people count (each.age <= 39 and each.age > 29);
	int nb_people_under_49 <- 0 update: people count (each.age <= 49 and each.age > 39);
	int nb_people_under_59 <- 0 update: people count (each.age <= 59 and each.age > 49);
	int nb_people_under_69 <- 0 update: people count (each.age <= 69 and each.age > 59);
	int nb_people_under_79 <- 0 update: people count (each.age <= 79 and each.age > 69);
	int nb_people_over_80 <- 0 update: people count (each.age >= 80);
	int nb_healthcare_workers <- 50 update: people count (each.is_healthcare_worker);
	int nb_recovered <- 0 update: people count (each.is_recovered);
	int nb_working_healthcare_workers <- 0 update: people count (each.is_healthcare_worker and each.objective = "working");
	float people_under_20_rate <- 0.331;
	float people_under_39_rate <- 0.299;
	float people_under_59_rate <- 0.231;
	float people_under_79_rate <- 0.119;
	float people_under_99_rate <- 0.019;

	// deaths
	int nb_deaths <- 0;
	int nb_female_deaths <- 0;
	int under_35_deaths <- 0;
	int over_35_deaths <- 0;
	int nb_deaths_hiccups <- 0;
	int nb_deaths_myalgia <- 0;
	int nb_deaths_both_symptoms <- 0;
	int nb_deaths_without_hiccups_myalgia <- 0;

	// disease spreading settings:
	float female_case_attack_rate <- 0.023; //since the females are the care givers, they are more vulnerable to the disease
	float male_case_attack_rate <- 0.022;
	float health_care_worker_attack_rate <- 0.476; // the risk of infection for the health care workers is 47.6%

	// disease mortality rates:
	float male_mortality_rate <- 0.333;
	float female_mortality_rate <- 0.455; // this represents the case fatality (number of deaths / number of total cases) per gender group
	float hiccups_myalgia_under_35_mortality_rate <- 0.778; // 77.8% of the patients with hiccups/myalgia will die (under 35)
	float under_35_mortality_rate <- 0.133; // 13.3% of the patients under 35 years old (without hiccups/myalgia) will die
	float hiccups_myalgia_35_up_mortality_rate <- 0.667;
	float over_35_mortality_rate <- 0.5;

	// symptoms rates:
	/*
     * https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4434807/ -> table 1
     */
	float hiccups_apparition_rate <- 0.09375; // 9.375% of the patients will develop hiccups
	float myalgia_apparition_rate <- 0.15625; // 15.625% of the patients will develop myalgia (muscular pain)

	// environmental settings:
	file roads_shapefile <- file("../includes/roads_dalaba.shp");
	file buildings_shapefile <- file("../includes/buildings_dalaba.shp");
	geometry shape <- envelope(roads_shapefile);
	//clean or not the data
	bool clean_data <- true;
	//tolerance for reconnecting nodes
	float tolerance <- 3.0;
	//if true, split the lines at their intersection
	bool split_lines <- true;
	//if true, keep only the main connected components of the network
	bool reduce_to_main_connected_components <- true;
	graph road_network;
	float asymptomatic_rate <- 0.271;
	float contact_rate_before_epidemic <- 0.7;
	int minimum_infection_cases_epidemic <- 3;
	building hospital;
	int nb_people_infected <- nb_infected_init update: people count (each.is_infected);
	int nb_people_not_infected <- nb_people - nb_infected_init update: nb_people - nb_people_infected - nb_recovered;
	int nb_females <- 0 update: people count (each.gender = 1);
	float infected_rate update: nb_people_infected / nb_people;

	init {
		starting_date <- date([2022, 1, 8, 7, 0, 0]);
		list<geometry> clean_lines <- clean_data ? clean_network(roads_shapefile.contents, tolerance, split_lines, reduce_to_main_connected_components) : roads_shapefile.contents;

		//create road from the clean lines
		create road from: clean_lines;
		road_network <- as_edge_graph(road);
		create building from: buildings_shapefile;
		create people number: nb_people {
			location <- any_location_in(one_of(building));
		}

		// mark the hospital
		ask 1 among building {
			is_hospital <- true;
		}

		// infect the people
		ask nb_infected_init among people {
			is_infected <- true;
		}
		
		// make the rest of the population susceptible
		list<people> remaining_people <- people where (!each.is_infected);
		ask remaining_people {
			is_susceptible <- true;
		}

		hospital <- one_of(building where each.is_hospital);

		// generate the age groups:
		ask int(nb_people * people_under_20_rate) among people {
			age <- rnd(7) + 12;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_39_rate) among remaining_people {
			age <- rnd(19) + 20;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_59_rate) among remaining_people {
			age <- rnd(19) + 40;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_79_rate) among remaining_people {
			age <- rnd(19) + 60;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_99_rate) among remaining_people {
			age <- rnd(19) + 80;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask remaining_people {
			age <- rnd(20) + 100;
		}

		list<people> working_people <- people where (each.age >= 22 and each.age <= 65);
		ask nb_healthcare_workers among working_people {
			is_healthcare_worker <- true;
			start_work <- rnd_choice([7::0.5, 19::0.5]);
			end_work <- start_work = 7 ? 19 : 7;
			if (start_work = 7) {
				objective <- "working";
				location <- any_location_in(hospital);
				is_at_work <- true;
			} else {
				objective <- "resting";
				location <- any_location_in(home);
				is_at_work <- false;
			}

		}

	}

	reflex declare_ebola_epidemic when: nb_people_infected >= minimum_infection_cases_epidemic {
		ebola_epidemic <- true;
	}

	reflex stop_ebola_epidemic when: nb_people_infected = 0 {
		ebola_epidemic <- false;
	}

	reflex end_simulation when: infected_rate = 1.0 or infected_rate = 0.0 or nb_people = 0 {
		do pause;
	}

}

species people skills: [moving] {
// location settings
	building home;
	bool at_home;
	point target;
	bool stays_home;

	// physical settings
	int gender;
	float health;
	int age;
	float speed;

	// career
	bool is_healthcare_worker <- false;
	string objective;
	bool is_at_work;
	int start_work;
	int end_work;

	// disease-related settings
	int infection_cycle <- 0;
	int symptoms_apparition_cycle <- 0;
	bool is_hospitalized <- false;
	bool asympt_handled <- false;
	float total_mortality_probability <- 0;
	list<string> symptoms <- [];
	bool is_infected <- false;
	bool is_symptomatic <- false;
	bool is_recovered <- false;
	bool is_susceptible;

	init {
		list<building> homes <- building where (each != hospital);
		home <- one_of(homes);
		health <- rnd(0.9) + 0.1;
		gender <- rnd_choice([0::0.5, 1::0.5]);
		age <- 0;
		at_home <- false;
		stays_home <- false;
		speed <- (2 + rnd(3)) #km / #h;
		is_susceptible <- false;
	}

	// basic movement actions
	reflex stay when: target = nil {
	// stay or move to one of the buildings
		if flip(travel_probability) and !(is_healthcare_worker and objective = "working") {
			target <- any_location_in(one_of(building));
		}

	}

	reflex move when: target != nil and !is_hospitalized and !stays_home {
		if (is_healthcare_worker and (objective = "resting" or (objective = "working") and !is_at_work)) or !is_healthcare_worker {
			do goto target: target on: road_network;
			if (location = target) {
				target <- nil;
				if (location = home.location) {
					at_home <- true;
				} else {
					at_home <- false;
				}

				if (is_healthcare_worker and objective = "working") {
					is_at_work <- true;
				}

			}

		}

	}

	// disease related actions
	reflex stay_at_home when: is_symptomatic and !is_hospitalized and is_infected and health <= 0.85 and ((ebola_epidemic and health > 0.7) or (!ebola_epidemic and health > 0.5)) {
		if !at_home {
		// go home and stay there
			do goto target: home.location on: road_network;
			if location = home.location {
				target <- nil;
				stays_home <- true;
				at_home <- true;
				is_at_work <- false;
				objective <- "resting";
			}

		}

	}

	reflex infect when: is_infected and is_symptomatic {
		ask people at_distance rnd(2) #m {
			float case_attack_rate <- 0;
			if (self.is_hospitalized and is_healthcare_worker) {
			// the patient is at the hospital
				case_attack_rate <- health_care_worker_attack_rate;
			} else {
				case_attack_rate <- (gender = 1) ? female_case_attack_rate : male_case_attack_rate;
			}

			if ((flip(case_attack_rate) and ebola_epidemic) or (flip(contact_rate_before_epidemic) and !ebola_epidemic)) and !is_infected and !is_recovered {
				is_infected <- true;
				is_susceptible <- false;
				asympt_handled <- flip(asymptomatic_rate);
			}

		}

	}

	reflex become_symptomatic when: is_infected and cycle >= infection_cycle + (rnd(19) + 2) #day / step and !asympt_handled and !is_symptomatic {
		is_symptomatic <- true;
		symptoms_apparition_cycle <- cycle;
		// add the symptoms
		if flip(hiccups_apparition_rate) and !(symptoms contains "hiccups") {
			add "hiccups" to: symptoms;
		}

		if flip(myalgia_apparition_rate) and !(symptoms contains "myalgia") {
			add "myalgia" to: symptoms;
		}

		// compute the mortality probability based on the age and simptoms
		switch (age) {
			match_between [0, 34] {
			// under 34 years old
				if symptoms contains "hiccups" or symptoms contains "myalgia" {
					total_mortality_probability <- hiccups_myalgia_under_35_mortality_rate;
				} else {
					total_mortality_probability <- under_35_mortality_rate;
				}

			}

			match_between [35, 100] {
			// 35 years old or older
				if symptoms contains "hiccups" or symptoms contains "myalgia" {
					total_mortality_probability <- hiccups_myalgia_35_up_mortality_rate;
				} else {
					total_mortality_probability <- over_35_mortality_rate;
				}

			}

		}

		if is_healthcare_worker {
			objective <- "resting";
		}

	}

	reflex get_sick when: is_infected and is_symptomatic and every(1 #hour) {
		if flip(total_mortality_probability) {
		// the agent will become sicker
			health <- health - rnd(0.3);
		} else if cycle >= infection_cycle + (rnd(14) + 2) #day / step or flip(0.2) {
		// the agent will feel better
			health <- health + rnd(0.1);
			if health > 1.0 {
				health <- 1.0;
			}

		}

	}

	reflex recover when: is_infected and cycle >= symptoms_apparition_cycle + (rnd(7) + 14) #day / step {
	// the agent will recover
		is_symptomatic <- false;
		is_recovered <- true;
		is_infected <- false;
		is_susceptible <- false;

		// the agent will not be hospitalized or he/she will be able to leave the house
		is_hospitalized <- false;
		stays_home <- false;
		at_home <- false;

		// update the agent's health
		health <- health + rnd(0.7);
		if health > 1.0 {
			health <- 1.0;
		}

	}

	reflex go_to_hospital when: (is_infected and is_symptomatic and ((health <= 0.7 and ebola_epidemic) or (!ebola_epidemic and health <= 0.5))) {
	// if the person is simptomatic and the ebola epidemic has been declared, go to the hospital. 
	//Otherwise, the person will wait to become sicker since the epidemic is not known.
		target <- any_location_in(hospital);
		do goto target: target on: road_network;
		target <- nil;
		is_hospitalized <- true;
		is_at_work <- false;
		stays_home <- false;
		at_home <- false;
		objective <- "resting";
	}

	// work-related actions
	reflex time_to_work when: is_healthcare_worker and current_date.hour = start_work and objective = "resting" and !is_symptomatic {
	// the agent (healthcare worker) will work
		objective <- "working";
		target <- any_location_in(hospital);
	}

	reflex time_to_go_home when: is_healthcare_worker and current_date.hour = end_work and objective = "working" and !is_symptomatic {
	// the healthcare worker will go home
		objective <- "resting";
		target <- any_location_in(home);
		do goto target: home.location on: road_network;
		is_at_work <- false;
	}

	// age related actions
	reflex get_old when: every(1 #year) and cycle >= 1 #year / step {
		age <- age + 1;
		write 'older';
	}

	// death
	reflex die when: health <= 0 {
		nb_deaths <- nb_deaths + 1;
		nb_people <- nb_people - 1;

		// gender mortality rates
		if (gender = 1) {
			nb_female_deaths <- nb_female_deaths + 1;
		}

		// age mortality rates
		switch (age) {
			match_between [0, 34] {
				under_35_deaths <- under_35_deaths + 1;
			}

			match_between [35, 100] {
				over_35_deaths <- over_35_deaths + 1;
			}

		}

		// symptoms mortality rates
		if symptoms contains "hiccups" and !(symptoms contains "myalgia") {
			nb_deaths_hiccups <- nb_deaths_hiccups + 1;
		} else if symptoms contains "myalgia" and !(symptoms contains "hiccups") {
			nb_deaths_myalgia <- nb_deaths_myalgia + 1;
		} else if symptoms contains "myalgia" and symptoms contains "hiccups" {
			nb_deaths_both_symptoms <- nb_deaths_both_symptoms + 1;
		} else {
			nb_deaths_without_hiccups_myalgia <- nb_deaths_without_hiccups_myalgia + 1;
		}

		do die;
	}

	aspect circle {
		rgb color <- #green;
		if is_infected {
			color <- #red;
		} else if is_susceptible {
			color <- #green;
		} else if is_recovered {
			color <- #purple;
		}

		draw circle(5) color: color;
	} }

	// road
species road {

	aspect geom {
		draw shape color: #black;
	}

}

// building
species building {
// if the building is a hospital
	bool is_hospital <- false;

	aspect geom {
		draw shape color: is_hospital ? #yellow : #gray;
	}

}

experiment ebolaspreadingmodel type: gui {
	parameter "The number of people infected at init" var: nb_infected_init min: 1 max: 700;
	parameter "The probability to leave the current building" var: travel_probability min: 0 max: 1;
	parameter "The minimum number of cases needed to declare the Ebola epidemic" var: minimum_infection_cases_epidemic min: 1 max: 350;
	parameter "The infection rate (before the epidemic is declared)" var: contact_rate_before_epidemic min: 0.0 max: 1.0;
	output {
		monitor "Deaths (under 34)" value: under_35_deaths;
		monitor "Deaths (over 35)" value: over_35_deaths;
		monitor "Remaining population" value: nb_people;
		monitor "Recovered" value: people count each.is_recovered;
		monitor "Infected people rate (total)" value: infected_rate;
		monitor "Currently infected people" value: nb_people_infected;
		monitor "Current day of the simulation" value: current_date;
		monitor "Population under 17 years old" value: nb_people_under_17;
		monitor "Population 18-29 years old" value: nb_people_under_29;
		monitor "Population 30-39 years old" value: nb_people_under_39;
		monitor "Population 40-49 years old" value: nb_people_under_49;
		monitor "Population 50-59 years old" value: nb_people_under_59;
		monitor "Population 60-69 years old" value: nb_people_under_69;
		monitor "Population 70-79 years old" value: nb_people_under_79;
		monitor "Population 80+" value: nb_people_over_80;
		monitor "Females" value: nb_females;
		monitor "Deaths" value: nb_deaths;
		monitor "Recovered" value: nb_recovered;
		monitor "Female deaths" value: nb_female_deaths;
		monitor "Deaths (persons who developed hiccups)" value: nb_deaths_hiccups;
		monitor "Deaths (persons who developed myalgia)" value: nb_deaths_myalgia;
		monitor "Deaths (persons who did not develop hiccups or myalgia)" value: nb_deaths_without_hiccups_myalgia;
		monitor "Deaths (persons who developed both symptoms)" value: nb_deaths_both_symptoms;
		display map {
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;
		}

		display chart_display refresh: every(10 #cycles) {
			chart "Disease spreading" type: series {
				data "susceptible" value: nb_people_not_infected color: #green;
				data "infected" value: nb_people_infected color: #red;
				data "recovered" value: nb_recovered color: #purple;
				data "deaths" value: nb_deaths color: #orange;
			}

		}

	}

}
